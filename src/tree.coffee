templateName = 'tree'
TemplateClass = Template[templateName]
selectEventName = 'select'
checkEventName = 'check'
hasSemanticUi = Package['nooitaf:semantic-ui']

TemplateClass.created = ->
  data = @data
  settings = getSettings()
  
  items = data.items
  @collection = Collections.get(data.collection ? items)
  unless @collection
    throw new Error('No collection provided')
  unless items
    items = @collection
  @items = items

  @model = data.model ? new TreeModel(collection: @collection)
  @selection = new SelectionModel(settings)
  @check = new SelectionModel(_.extend({}, settings, {multiSelect: true}))
  # Allow modifying the underlying logic of the tree model.
  _.extend(@model, data.settings)

TemplateClass.rendered = ->
  data = @data
  items = data.items
  cursor = Collections.getCursor(items)
  settings = getSettings()

  $tree = @$tree = @$('.tree')
  model = @model
  docs = Collections.getItems(items)
  treeData = model.docsToNodeData(docs)
  treeArgs =
    data: treeData
    autoOpen: settings.autoExpand
    selectable: settings.selectable
  if settings.checkboxes
    treeArgs.onCreateLi = onCreateNode.bind(null, @)
  $tree.tree(treeArgs)

  # Only a reactive cursor can observe for changes. A simple array can only render a tree once.
  return unless cursor
  @autorun ->

    Collections.observe cursor,
      added: (newDoc) ->
        data = model.docToNodeData(newDoc, {children: false})
        sortResults = getSortedIndex($tree, newDoc)
        nextSiblingNode = sortResults.nextSiblingNode
        if nextSiblingNode
          $tree.tree('addNodeBefore', data, nextSiblingNode)
        else
          $tree.tree('appendNode', data, sortResults.parentNode)

      changed: (newDoc, oldDoc) ->
        node = getNode($tree, newDoc._id)
        # Only get one level of children and find their nodes. Children in deeper levels will be
        # updated by their own parents.
        data = model.docToNodeData(newDoc, {children: false})
        childDocs = model.getChildren(newDoc)
        data.children = _.map childDocs, (childDoc) ->
          getNode($tree, childDoc._id)
        $tree.tree('updateNode', node, data)
        parent = newDoc.parent
        if parent != oldDoc.parent
          sortResults = getSortedIndex($tree, newDoc)
          nextSiblingNode = sortResults.nextSiblingNode
          if nextSiblingNode
            $tree.tree('moveNode', node, nextSiblingNode, 'before')
          else
            $tree.tree('moveNode', node, sortResults.parentNode, 'inside')

      removed: (oldDoc) ->
        id = oldDoc._id
        node = getNode($tree, id)
        removeSelection($tree, [id])
        $tree.tree('removeNode', node)

TemplateClass.destory = ->
  _.each @checkboxes, ($checkbox) ->
    # Remove bound events.
    $checkbox.off()

TemplateClass.events
  'tree.select .tree': (e, template) -> handleSelectionEvent(e, template)
  'tree.click .tree': (e, template) -> handleClickEvent(e, template)
  'tree.dblclick .tree': (e, template) ->
    id = e.node.id

####################################################################################################
# EXPANSION
####################################################################################################

expandNode = ($tree, id) -> $tree.tree('openNode', getNode($tree, id))

collapseNode = ($tree, id) -> $tree.tree('closeNode', getNode($tree, id))

####################################################################################################
# SELECTION
####################################################################################################

# A generic class for representing the selection of items.
class SelectionModel

  constructor: (args) ->
    args = _.extend({
      multiSelect: true
    }, args)
    @selectedIds = new ReactiveVar([])
    @multiSelect = args.multiSelect

  setSelectedIds: (ids) ->
    selectedIds = @getSelectedIds()
    toDeselectIds = _.difference(selectedIds, ids)
    toSelectIds = _.difference(ids, selectedIds)
    @removeSelection(toDeselectIds)
    @addSelection(toSelectIds)
    {deselectedIds: toDeselectIds, selectedIds: toSelectIds}

  getSelectedIds: -> @selectedIds.get()

  deselectAll: ->
    selectedIds = @getSelectedIds()
    @removeSelection(selectedIds)
    selectedIds

  toggleSelection: (ids) ->
    selectedIds = @getSelectedIds()
    toDeselectIds = _.intersection(selectedIds, ids)
    toSelectIds = _.difference(ids, selectedIds)
    _.extend(@removeSelection(toDeselectIds), @addSelection(toSelectIds))

  addSelection: (ids) ->
    selectedIds = @getSelectedIds()
    toSelectIds = _.difference(ids, selectedIds)
    newSelectedIds = _.union(selectedIds, toSelectIds)
    if toSelectIds.length > 0
      if @multiSelect == false
        @deselectAll()
        if newSelectedIds.length > 1
          newSelectedIds = toSelectIds = [ids[0]]
      @selectedIds.set(newSelectedIds)
    {selectedIds: toSelectIds, deselectedIds: []}

  removeSelection: (ids) ->
    selectedIds = @getSelectedIds()
    toDeselectIds = _.intersection(selectedIds, ids)
    newSelectedIds = _.difference(selectedIds, toDeselectIds)
    @selectedIds.set(newSelectedIds)
    {selectedIds: [], deselectedIds: toDeselectIds}

setSelectedIds = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.setSelectedIds(ids)
  handleSelectionResult(domNode, result)

getSelectedIds = (domNode) -> getTemplate(domNode).selection.getSelectedIds()

deselectAll = (domNode) ->
  return unless isSelectable(domNode)
  selectedIds = getTemplate(domNode).selection.deselectAll()
  handleSelectionResult(domNode, {selectedIds: selectedIds, deselectedIds: []})

toggleSelection = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.toggleSelection(ids)
  handleSelectionResult(domNode, result)

addSelection = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.addSelection(ids)
  handleSelectionResult(domNode, result)

removeSelection = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.removeSelection(ids)
  handleSelectionResult(domNode, result)

handleSelectionResult = (domNode, result) ->
  $tree = getTreeElement(domNode)
  _.each result.selectedIds, (id) -> _selectNode($tree, id)
  _.each result.deselectedIds, (id) -> _deselectNode($tree, id)
  $tree.trigger(selectEventName, result)

selectNode = (domNode, id) -> addSelection(domNode, [id])

deselectNode = (domNode, id) -> removeSelection(domNode, [id])

_selectNode = (domNode, id) ->
  $tree = getTreeElement(domNode)
  $tree.tree('addToSelection', getNode($tree, id))

_deselectNode = (domNode, id) ->
  $tree = getTreeElement(domNode)
  $tree.tree('removeFromSelection', getNode($tree, id))

isNodeSelected = (domNode, id) ->
  $tree = getTreeElement(domNode)
  !!$tree.tree('isNodeSelected', getNode($tree, id))

handleSelectionEvent = (e, template) ->
  $tree = template.$tree
  multiSelect = template.selection.multiSelect
  selectedNode = e.node
  return unless selectedNode
  selectedId = selectedNode.id
  if multiSelect
    selectNode($tree, selectedId)
  else
    setSelectedIds($tree, [selectedId])

handleClickEvent = (e, template) ->
  return unless isSelectable(template)
  $tree = template.$tree
  multiSelect = template.selection.multiSelect
  selectedNode = e.node
  selectedId = selectedNode.id
  # Disable single selection behaviour from taking effect.
  e.preventDefault()
  if multiSelect && e.click_event.metaKey
    if isNodeSelected($tree, selectedId)
      deselectNode($tree, selectedId)
    else
      selectNode($tree, selectedId)
  else
    setSelectedIds($tree, [selectedId])

isSelectable = (template) -> getSettings(template).selectable

isCheckable = (template) -> getSettings(template).checkboxes

####################################################################################################
# CHECKBOXES
####################################################################################################

onCreateNode = (template, node, $em) ->
  $tree = template.$tree
  settings = getSettings(template)
  checkboxes = template.checkboxes ?= []
  if settings.checkboxes
    $title = $('.jqtree-title', $em)
    $checkbox = $('<input class="checkbox" type="checkbox" />')
    $title.before($checkbox)
    checkboxes.push($checkbox)
    $checkbox.on 'click', (e) -> e.stopPropagation()
    $checkbox.on 'change', ->
      isChecked = $checkbox.is(':checked')
      id = node.id
      if isChecked
        checkNode($tree, id)
      else
        uncheckNode($tree, id)
  $selectRow = $('<div class="jqtree-select-row"></div>')
  $('.jqtree-element', $em).append($selectRow)

setCheckedIds = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.setSelectedIds(ids)
  handleCheckResult(domNode, result)

getCheckedIds = (domNode) -> getTemplate(domNode).check.getCheckedIds()

uncheckAll = (domNode) ->
  return unless isCheckable(domNode)
  checkedIds = getTemplate(domNode).check.deselectAll()
  handleCheckResult(domNode, {selectedIds: checkedIds, deselectedIds: []})

toggleChecked = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.toggleSelection(ids)
  handleCheckResult(domNode, result)

addChecked = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.addSelection(ids)
  handleCheckResult(domNode, result)

removeChecked = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.removeSelection(ids)
  handleCheckResult(domNode, result)

handleCheckResult = (domNode, result) ->
  $tree = getTreeElement(domNode)
  result.checkedIds = result.selectedIds
  result.uncheckedIds = result.deselectedIds
  delete result.selectedIds
  delete result.deselectedIds
  _.each result.checkedIds, (id) -> _checkNode($tree, id)
  _.each result.uncheckedIds, (id) -> _uncheckNode($tree, id)
  $tree.trigger(checkEventName, result)

checkNode = (domNode, id) -> addChecked(domNode, [id])

uncheckNode = (domNode, id) -> removeChecked(domNode, [id])

_getCheckbox = (domNode, id) ->
  $tree = getTreeElement(domNode)
  node = getNode($tree, id)
  $('> .jqtree-element > .checkbox', node.element)

_checkNode = (domNode, id) -> _getCheckbox(domNode, id).prop('checked', true)

_uncheckNode = (domNode, id) -> _getCheckbox(domNode, id).prop('checked', false)

isNodeChecked = (domNode, id) -> _getCheckbox(domNode, id).prop('checked')

####################################################################################################
# AUXILIARY
####################################################################################################

getDomNode = (template) ->
  unless template then throw new Error('No template provided')
  template.find('.tree')

getTemplate = (arg) ->
  if arg instanceof Blaze.TemplateInstance
    template = arg
  else
    domNode = $(arg)[0]
    if domNode
      return Blaze.getView(domNode).templateInstance()
  try
    Templates.getNamedInstance(templateName, template)
  catch err
    throw new Error('No domNode provided')

getTreeElement = (domNode) ->
  domNode = $(domNode)[0]
  startTemplate = Blaze.getView(domNode)?.templateInstance()
  template = Templates.getNamedInstance(templateName, startTemplate)
  unless template
    throw new Error('No template could be found.')
  template.$tree

getSettings = (arg) ->
  template = getTemplate(arg)
  unless template.settings
    template.settings = _.extend({
      autoExpand: true
      multiSelect: false
      selectable: true
      checkboxes: false
    }, template.data.settings)
  template.settings

####################################################################################################
# NODES
####################################################################################################

getNode = ($tree, id) -> $tree.tree('getNodeById', id)

getRootNode = ($tree) -> $tree.tree('getTree')

getParentNode = ($tree, parent) ->
  if parent
    getNode($tree, parent)
  else
    getRootNode($tree)

getSortedIndex = ($tree, doc) ->
  template = getTemplate($tree)
  $tree = template.$tree
  model = template.model
  collection = template.collection
  parent = model.getParent(doc)
  parentNode = getParentNode($tree, parent)
  # This array will include the doc itself.
  siblings = model.getChildren(collection.findOne(parent))
  siblings.sort(model.compareDocs)
  maxIndex = siblings.length - 1
  sortedIndex = maxIndex
  _.some siblings, (sibling, i) ->
    if sibling._id == doc._id
      sortedIndex = i
  if siblings.length > 1 && sortedIndex != maxIndex
    nextSiblingDoc = siblings[sortedIndex + 1]
    nextSiblingNode = getNode($tree, nextSiblingDoc._id)
    # $tree.tree('addNodeBefore', data, nextSiblingNode)
    # $tree.tree('appendNode', data, parentNode)
  # else
  result =
    siblings: siblings
    maxIndex: maxIndex
    sortedIndex: sortedIndex
    nextSiblingNode: nextSiblingNode
    parentNode: parentNode

####################################################################################################
# MODEL
####################################################################################################

class TreeModel

  constructor: (args) ->
    @collection = args.collection
    unless @collection
      throw new Error('No collection provided when creating tree data')
  
  getChildren: (doc) ->
    # Search for root document if doc is undefined
    id = doc?._id ? null
    children = @collection.find({parent: id}).fetch()
    children.sort(@compareDocs)
    children
  
  hasChildren: (doc) -> @getChildren(doc).length == 0

  getParent: (doc) -> doc.parent

  hasParent: (doc) -> @getParent(doc)?

  docToNodeData: (doc, args) ->
    args = _.extend({
      children: true
    }, args)
    data =
      id: doc._id
      label: doc.name
    if args.children
      childrenDocs = @getChildren(doc)
      childrenData = _.map childrenDocs, @docToNodeData, @
      data.children = childrenData
    data

  docsToNodeData: (docs) ->
    data = []
    rootDocs = _.filter docs, (doc) => !@hasParent(doc)
    rootDocs.sort(@compareDocs)
    _.each rootDocs, (doc) =>
      datum = @docToNodeData(doc)
      data.push(datum)
    data

  compareDocs: (docA, docB) ->
    if docA.name < docB.name then -1 else 1

####################################################################################################
# API
####################################################################################################

_.extend(TemplateClass, {
  getDomNode: getDomNode
  getTemplate: getTemplate
  getSettings: getSettings
  
  expandNode: expandNode
  collapseNode: collapseNode
  
  selectNode: selectNode
  deselectNode: deselectNode
  setSelectedIds: setSelectedIds
  getSelectedIds: getSelectedIds
  deselectAll: deselectAll
  addSelection: addSelection
  removeSelection: removeSelection
  isNodeSelected: isNodeSelected,

  checkNode: checkNode
  uncheckNode: uncheckNode
  setCheckedIds: setCheckedIds
  getCheckedIds: getCheckedIds
  uncheckAll: uncheckAll
  toggleChecked: toggleChecked
  addChecked: addChecked
  removeChecked: removeChecked
  handleCheckResult: handleCheckResult
  isNodeChecked: isNodeChecked
})
