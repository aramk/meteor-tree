templateName = 'tree'
TemplateClass = Template[templateName]
selectEventName = 'select'
checkEventName = 'check'

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
  @selection = new IdSet({exclusive: !settings.multiSelect})
  @check = new IdSet({exclusive: false})
  # Allow modifying the underlying logic of the tree model.
  _.extend(@model, data.settings)

TemplateClass.rendered = ->
  data = @data
  model = @model
  items = data.items
  cursor = Collections.getCursor(items)
  settings = getSettings()
  $tree = @$tree = @$('.tree')
  loadTree(@)

  # Only a reactive cursor can observe for changes. A simple array can only render a tree once.
  return unless cursor
  @autorun ->

    Collections.observe cursor,
      added: (newDoc) ->
        id = newDoc._id
        data = model.docToNodeData(newDoc, {children: false})
        docParentId = model.getParent(data)
        unless docParentId
          # There is a significant memory leak caused by re-loading the entire tree after each
          # change (e.g. if a node is added to the root node). Hence, we recreate the entire tree
          # just once after all updates are complete.
          refreshTree($tree)
          return
        sortResults = getSortedIndex($tree, newDoc)
        nextSiblingNode = sortResults.nextSiblingNode
        if nextSiblingNode
          $tree.tree('addNodeBefore', data, nextSiblingNode)
        else
          $tree.tree('appendNode', data, sortResults.parentNode)
        autoExpand = getSettings($tree).autoExpand
        if autoExpand
          expandNode($tree, id)
        parentNode = getNode($tree, id).parent
        parentId = parentNode.id
        # Root node doesn't have an ID and cannot be expanded.
        if autoExpand && parentId
          expandNode($tree, parentId)

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
        # If the parent node is removed before the child, it will no longer exist and doesn't need
        # to be removed.
        return unless node
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
# LOADING
####################################################################################################

loadTree = (domNode) ->
  template = getTemplate(domNode)
  $em = $(getDomNode(domNode))
  getTreeElement(domNode).remove()
  $tree = createTreeElement()
  $em.append($tree)
  model = template.model
  docs = Collections.getItems(template.items)
  treeData = model.docsToNodeData(docs)
  settings = getSettings(domNode)
  treeArgs =
    data: treeData
    autoOpen: settings.autoExpand
    selectable: settings.selectable
  if settings.checkboxes
    treeArgs.onCreateLi = onCreateNode.bind(null, template)
  $tree.tree(treeArgs)

refreshTree = _.debounce(loadTree, 1000)

####################################################################################################
# EXPANSION
####################################################################################################

expandNode = ($tree, id) -> $tree.tree('openNode', getNode($tree, id))

collapseNode = ($tree, id) -> $tree.tree('closeNode', getNode($tree, id))

####################################################################################################
# SELECTION
####################################################################################################

setSelectedIds = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.setIds(ids)
  handleSelectionResult(domNode, result)

getSelectedIds = (domNode) -> getTemplate(domNode).selection.getIds()

deselectAll = (domNode) ->
  return unless isSelectable(domNode)
  selectedIds = getTemplate(domNode).selection.removeAll()
  handleSelectionResult(domNode, {added: selectedIds, removed: []})

toggleSelection = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.toggle(ids)
  handleSelectionResult(domNode, result)

addSelection = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.add(ids)
  handleSelectionResult(domNode, result)

removeSelection = (domNode, ids) ->
  return unless isSelectable(domNode)
  result = getTemplate(domNode).selection.remove(ids)
  handleSelectionResult(domNode, result)

handleSelectionResult = (domNode, result) ->
  $tree = getTreeElement(domNode)
  _.each result.added, (id) -> _selectNode($tree, id)
  _.each result.removed, (id) -> _deselectNode($tree, id)
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
  multiSelect = !template.selection.exclusive
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
  multiSelect = !template.selection.exclusive
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
    # TODO(aramk) Remove this reference and call off() on node removal.
    checkboxes.push($checkbox)
    $checkbox.prop('checked', template.check.contains(node.id))
    $checkbox.on 'click', (e) -> e.stopPropagation()
    $checkbox.on 'change', (e) ->
      isChecked = $checkbox.is(':checked')
      id = node.id
      if isChecked
        checkNode($tree, id)
      else
        uncheckNode($tree, id)
      if settings.recursiveCheck
        _.each getNode($tree, id).children, (childNode) ->
          # Check all children and trigger a change event so it's recursive.
          getCheckbox($tree, childNode.id).prop('checked', isChecked).trigger('change')

  $selectRow = $('<div class="jqtree-select-row"></div>')
  $('.jqtree-element', $em).append($selectRow)

setCheckedIds = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.setIds(ids)
  handleCheckResult(domNode, result)

getCheckedIds = (domNode) -> getTemplate(domNode).check.getIds()

uncheckAll = (domNode) ->
  return unless isCheckable(domNode)
  selectedIds = getTemplate(domNode).check.removeAll()
  handleCheckResult(domNode, {added: selectedIds, removed: []})

toggleChecked = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.toggle(ids)
  handleCheckResult(domNode, result)

addChecked = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.add(ids)
  handleCheckResult(domNode, result)

removeChecked = (domNode, ids) ->
  return unless isCheckable(domNode)
  result = getTemplate(domNode).check.remove(ids)
  handleCheckResult(domNode, result)

handleCheckResult = (domNode, result) ->
  $tree = getTreeElement(domNode)
  _.each result.added, (id) -> _checkNode($tree, id)
  _.each result.removed, (id) -> _uncheckNode($tree, id)
  $tree.trigger(checkEventName, result)

checkNode = (domNode, id) -> addChecked(domNode, [id])

uncheckNode = (domNode, id) -> removeChecked(domNode, [id])

getCheckbox = (domNode, id) ->
  $tree = getTreeElement(domNode)
  node = getNode($tree, id)
  $('> .jqtree-element > .checkbox', node.element)

_checkNode = (domNode, id) -> getCheckbox(domNode, id).prop('checked', true)

_uncheckNode = (domNode, id) -> getCheckbox(domNode, id).prop('checked', false)

isNodeChecked = (domNode, id) -> getCheckbox(domNode, id).prop('checked')

####################################################################################################
# AUXILIARY
####################################################################################################

getDomNode = (arg) ->
  template = getTemplate(arg)
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

getTreeElement = (arg) ->
  template = getTemplate(arg)
  template.$('.tree-inner')

createTreeElement = -> $('<div class="tree-inner"></div>')

getSettings = (arg) ->
  template = getTemplate(arg)
  unless template.settings
    template.settings = _.extend({
      autoExpand: true
      multiSelect: false
      selectable: true
      checkboxes: false
      recursiveCheck: true
    }, template.data.settings)
  template.settings

####################################################################################################
# NODES
####################################################################################################

getNode = ($tree, id) -> $tree.tree('getNodeById', id)

getRootNode = ($tree) -> $tree.tree('getTree')

getSortedIndex = ($tree, doc) ->
  template = getTemplate($tree)
  $tree = template.$tree
  model = template.model
  collection = template.collection
  parent = model.getParent(doc)
  if parent
    parentNode = getNode($tree, parent)
  else
    parentNode = getRootNode($tree)
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


class IdSet

  constructor: (args) ->
    args = _.extend({
      exclusive: false
    }, args)
    @ids = new ReactiveVar([])
    @idsMap = {}
    @exclusive = args.exclusive

  setIds: (ids) ->
    existingIds = @getIds()
    toRemove = _.difference(existingIds, ids)
    toAdd = _.difference(ids, existingIds)
    @remove(toRemove)
    @add(toAdd)
    {added: toAdd, removed: toRemove}

  getIds: -> @ids.get()

  add: (ids) ->
    existingIds = @getIds()
    toAdd = _.difference(ids, existingIds)
    newIds = _.union(existingIds, toAdd)
    if toAdd.length > 0
      if @exclusive
        @removeAll()
        if newIds.length > 1
          newIds = toAdd = [ids[0]]
      @ids.set(newIds)
    _.each toAdd, (id) => @idsMap[id] = true
    {added: toAdd, removed: []}

  remove: (ids) ->
    existingIds = @getIds()
    toRemove = _.intersection(existingIds, ids)
    newIds = _.difference(existingIds, toRemove)
    @ids.set(newIds)
    _.each toRemove, (id) => delete @idsMap[id]
    {added: [], removed: toRemove}

  removeAll: ->
    toRemove = @getIds()
    @remove(toRemove)
    toRemove

  toggle: (ids) ->
    existingIds = @getIds()
    toRemove = _.intersection(existingIds, ids)
    toAdd = _.difference(ids, existingIds)
    _.extend(@remove(toRemove), @add(toAdd))

  contains: (id) -> !!@idsMap[id]

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
