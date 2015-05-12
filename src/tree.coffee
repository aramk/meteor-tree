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
  _.extend(@model, settings)

TemplateClass.rendered = ->
  data = @data
  model = @model
  items = @items
  settings = getSettings()
  template = @
  # loadTree(@)
  refreshTree(@)

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

loadTree = (element) ->
  template = getTemplate(element)
  $em = getElement(element)
  getTreeElement(element).remove()
  $tree = createTreeElement()
  $em.append($tree)
  model = template.model
  docs = Collections.getItems(template.items)
  treeData = model.docsToNodeData(docs)
  settings = getSettings(element)
  treeArgs =
    data: treeData.data
    autoOpen: settings.autoExpand
    selectable: settings.selectable
  treeArgs.onCreateLi = onCreateNode.bind(null, template)

  # Check all new items if needed.
  if settings.checked
    template.check.setIds(_.keys(treeData.visited.ids))

  $tree.tree(treeArgs)
  setUpReactiveUpdates(template)

# refreshTree = Functions.debounceLeft(loadTree, 1000)
refreshTree = _.debounce(loadTree, 1000)

setUpReactiveUpdates = (template) ->
  return if template.isReactiveSetup

  # Only a reactive cursor can observe for changes. A simple array can only render a tree once.
  cursor = Collections.getCursor(template.items)
  return unless cursor

  settings = getSettings(template)
  model = template.model

  template.autorun ->

    Collections.observe cursor,
      added: (newDoc) ->
        id = newDoc._id
        data = model.docToNodeData(newDoc, {children: false})
        # Check all new items if needed.
        if settings.checked then template.check.add([id])
        docParentId = model.getParent(data)
        unless docParentId
          # There is a significant memory leak caused by re-loading the entire tree after each
          # change (e.g. if a node is added to the root node). Hence, we recreate the entire tree
          # just once after all updates are complete.
          refreshTree(template)
          return
        sortResults = getSortedIndex(template, newDoc)
        nextSiblingNode = sortResults.nextSiblingNode
        $tree = getTreeElement(template)
        if nextSiblingNode
          $tree.tree('addNodeBefore', data, nextSiblingNode)
        else
          $tree.tree('appendNode', data, sortResults.parentNode)
        autoExpand = settings.autoExpand
        if autoExpand
          expandNode(template, id)
        parentNode = getNode(template, id).parent
        parentId = parentNode.id
        # Root node doesn't have an ID and cannot be expanded.
        if autoExpand && parentId
          expandNode(template, parentId)

      changed: (newDoc, oldDoc) ->
        node = getNode(template, newDoc._id)
        # Only get one level of children and find their nodes. Children in deeper levels will be
        # updated by their own parents.
        data = model.docToNodeData(newDoc, {children: false})
        childDocs = model.getChildren(newDoc)
        data.children = _.map childDocs, (childDoc) ->
          getNode(template, childDoc._id)
        $tree = getTreeElement(template)
        $tree.tree('updateNode', node, data)
        parent = newDoc.parent
        if parent != oldDoc.parent
          sortResults = getSortedIndex(template, newDoc)
          nextSiblingNode = sortResults.nextSiblingNode
          if nextSiblingNode
            $tree.tree('moveNode', node, nextSiblingNode, 'before')
          else
            $tree.tree('moveNode', node, sortResults.parentNode, 'inside')

      removed: (oldDoc) ->
        id = oldDoc._id
        node = getNode(template, id)
        # If the parent node is removed before the child, it will no longer exist and doesn't need
        # to be removed.
        return unless node
        removeSelection(template, [id])
        $tree = getTreeElement(template)
        $tree.tree('removeNode', node)

  template.isReactiveSetup = true

####################################################################################################
# EXPANSION
####################################################################################################

expandNode = (element, id) -> getTreeElement(element).tree('openNode', getNode(element, id))

collapseNode = (element, id) -> getTreeElement(element).tree('closeNode', getNode(element, id))

####################################################################################################
# SELECTION
####################################################################################################

setSelectedIds = (element, ids) ->
  return unless isSelectable(element)
  result = getTemplate(element).selection.setIds(ids)
  handleSelectionResult(element, result)

getSelectedIds = (element) -> getTemplate(element).selection.getIds()

deselectAll = (element) ->
  return unless isSelectable(element)
  selectedIds = getTemplate(element).selection.removeAll()
  handleSelectionResult(element, {added: selectedIds, removed: []})

toggleSelection = (element, ids) ->
  return unless isSelectable(element)
  result = getTemplate(element).selection.toggle(ids)
  handleSelectionResult(element, result)

addSelection = (element, ids) ->
  return unless isSelectable(element)
  result = getTemplate(element).selection.add(ids)
  handleSelectionResult(element, result)

removeSelection = (element, ids) ->
  return unless isSelectable(element)
  result = getTemplate(element).selection.remove(ids)
  handleSelectionResult(element, result)

handleSelectionResult = (element, result) ->
  _.each result.added, (id) -> _selectNode(element, id)
  _.each result.removed, (id) -> _deselectNode(element, id)
  getTreeElement(element).trigger(selectEventName, result)

selectNode = (element, id) -> addSelection(element, [id])

deselectNode = (element, id) -> removeSelection(element, [id])

_selectNode = (element, id) ->
  getTreeElement(element).tree('addToSelection', getNode(element, id))

_deselectNode = (element, id) ->
  getTreeElement(element).tree('removeFromSelection', getNode(element, id))

isNodeSelected = (element, id) ->
  !!getTreeElement(element).tree('isNodeSelected', getNode(element, id))

handleSelectionEvent = (e, template) ->
  multiSelect = !template.selection.exclusive
  selectedNode = e.node
  return unless selectedNode
  selectedId = selectedNode.id
  if multiSelect
    selectNode(template, selectedId)
  else
    setSelectedIds(template, [selectedId])

handleClickEvent = (e, template) ->
  return unless isSelectable(template)
  multiSelect = !template.selection.exclusive
  selectedNode = e.node
  selectedId = selectedNode.id
  # Disable single selection behaviour from taking effect.
  e.preventDefault()
  if multiSelect && e.click_event.metaKey
    if isNodeSelected(template, selectedId)
      deselectNode(template, selectedId)
    else
      selectNode(template, selectedId)
  else
    setSelectedIds(template, [selectedId])

isSelectable = (template) -> getSettings(template).selectable

isCheckable = (template) -> getSettings(template).checkboxes

####################################################################################################
# CHECKBOXES
####################################################################################################

onCreateNode = (template, node, $em) ->
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
        checkNode(template, id)
      else
        uncheckNode(template, id)
      if settings.recursiveCheck
        _.each getNode(template, id).children, (childNode) ->
          # Check all children and trigger a change event so it's recursive.
          getCheckbox(template, childNode.id).prop('checked', isChecked).trigger('change')
  callback = settings.onCreateNode
  if callback
    callback.apply(@, arguments)
  # Add selection element which is shown when the row is selected.
  $selectRow = $('<div class="jqtree-select-row"></div>')
  $('.jqtree-element', $em).append($selectRow)

setCheckedIds = (element, ids) ->
  return unless isCheckable(element)
  result = getTemplate(element).check.setIds(ids)
  handleCheckResult(element, result)

getCheckedIds = (element) -> getTemplate(element).check.getIds()

setAllChecked = (element, check) ->
  check ?= true
  template = getTemplate(element)
  return unless isCheckable(element)
  if check
    ids = template.collection.find().forEach (doc) -> doc._id
    changedIds = template.check.setIds(ids).added
    handleCheckResult(element, {added: changedIds, removed: []})
  else
    changedIds = template.check.removeAll()
    handleCheckResult(element, {added: [], removed: changedIds})

toggleChecked = (element, ids) ->
  return unless isCheckable(element)
  result = getTemplate(element).check.toggle(ids)
  handleCheckResult(element, result)

addChecked = (element, ids) ->
  return unless isCheckable(element)
  result = getTemplate(element).check.add(ids)
  handleCheckResult(element, result)

removeChecked = (element, ids) ->
  return unless isCheckable(element)
  result = getTemplate(element).check.remove(ids)
  handleCheckResult(element, result)

handleCheckResult = (element, result) ->
  _.each result.added, (id) -> _checkNode(element, id)
  _.each result.removed, (id) -> _uncheckNode(element, id)
  getTreeElement(element).trigger(checkEventName, result)

checkNode = (element, id) -> addChecked(element, [id])

uncheckNode = (element, id) -> removeChecked(element, [id])

getCheckbox = (element, id) ->
  node = getNode(element, id)
  $('> .jqtree-element > .checkbox', node.element)

_checkNode = (element, id) -> getCheckbox(element, id).prop('checked', true)

_uncheckNode = (element, id) -> getCheckbox(element, id).prop('checked', false)

isNodeChecked = (element, id) -> getCheckbox(element, id).prop('checked')

####################################################################################################
# AUXILIARY
####################################################################################################

getElement = (arg) ->
  template = getTemplate(arg)
  unless template then throw new Error('No template provided')
  template.$('.tree')

getTemplate = (arg) ->
  if arg instanceof Blaze.TemplateInstance
    template = arg
  else
    element = $(arg)[0]
    if element
      return Blaze.getView(element).templateInstance()
  try
    Templates.getNamedInstance(templateName, template)
  catch err
    throw new Error('No element provided')

getTreeElement = (arg) -> getTemplate(arg).$('.tree-inner')

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

getNode = (element, id) -> getTreeElement(element).tree('getNodeById', id)

getRootNode = (element) -> getTreeElement(element).tree('getTree')

getSortedIndex = (element, doc) ->
  template = getTemplate(element)
  element = getElement(template)
  model = template.model
  collection = template.collection
  parent = model.getParent(doc)
  if parent
    parentNode = getNode(element, parent)
  else
    parentNode = getRootNode(element)
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
    nextSiblingNode = getNode(element, nextSiblingDoc._id)
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
  
  getChildren: (doc, args) ->
    args ?= {}
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
      visited: {count: 0, ids: {}}
    }, args)
    return if args.visited.ids[doc._id]# || args.visited.count >= 200

    args.visited.ids[doc._id] = true
    args.visited.count++
    data =
      id: doc._id
      label: doc.name
    if args.children
      childrenDocs = @getChildren(doc)
      childrenData = []
      _.each childrenDocs, (childDoc) =>
        childData = @docToNodeData(childDoc, args)
        if childData then childrenData.push(childData)
      data.children = childrenData
    data

  docsToNodeData: (docs) ->
    data = []
    rootDocs = _.filter docs, (doc) => !@hasParent(doc)
    rootDocs.sort(@compareDocs)
    args = {visited: {count: 0, ids: {}}}
    _.each rootDocs, (doc) =>
      datum = @docToNodeData(doc, args)
      data.push(datum)
    Setter.merge {data: data}, args

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

  toggle: (ids, enabled) ->
    existingIds = @getIds()
    toRemove = _.intersection(existingIds, ids)
    toAdd = _.difference(ids, existingIds)
    _.extend(@remove(toRemove), @add(toAdd))

  contains: (id) -> !!@idsMap[id]

####################################################################################################
# API
####################################################################################################

_.extend(TemplateClass, {
  getElement: getElement
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
  setAllChecked: setAllChecked
  toggleChecked: toggleChecked
  addChecked: addChecked
  removeChecked: removeChecked
  handleCheckResult: handleCheckResult
  isNodeChecked: isNodeChecked
})
