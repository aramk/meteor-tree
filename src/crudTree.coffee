templateName = 'crudTree'
TemplateClass = Template[templateName]
selectEventName = 'select'
checkEventName = 'check'

TemplateClass.created = ->
  @selectionItemsStyle = new ReactiveVar('')

TemplateClass.rendered = ->
  data = @data
  @$tree = @$('.tree')
  treeTemplate = Template.tree.getTemplate(@$tree)
  @collection = treeTemplate.collection

  collectionName = data.collectionName ? Collections.getName(collection)
  if collectionName
    collectionId = Strings.firstToLowerCase(Strings.singular(collectionName))
    @createRoute = data.createRoute ? collectionId + 'Create'
    @editRoute = data.editRoute ? collectionId + 'Edit'
  else
    console.warn('No collection name provided', data)

  @autorun =>
    selectedIds = Template.tree.getSelectedIds(@$tree)
    @selectionItemsStyle.set(if selectedIds.length > 0 then '' else 'display: none')

TemplateClass.helpers
  selectionItemsStyle: -> getTemplate().selectionItemsStyle.get()

TemplateClass.events
  'click .create.item': (e, template) -> createItem(template)
  'tree.dblclick .tree': (e, template) -> editItem(template, {ids: [e.node.id]})
  'click .edit.item': (e, template) -> editItem(template)
  'click .delete.item': (e, template) -> deleteItem(template)

####################################################################################################
# CRUD
####################################################################################################

createItem = (template) ->
  settings = getSettings(template)
  if settings.onCreate
    settings.onCreate(createHandlerContext(template))
  else
    typeof Router != 'undefined' && Router.go(template.createRoute)

editItem = (template, args) ->
  settings = getSettings(template)
  defaultHandler = ->
    ids = args.ids ? Template.tree.getSelectedIds(template.$tree)
    id = ids[0]
    typeof Router != 'undefined' && Router.go(editRoute, {
      _id: id
    })
  if settings.onEdit
    settings.onEdit(createHandlerContext(template, _.extend({
      defaultHandler: defaultHandler
    }, args)))
  else
    defaultHandler()

deleteItem = (template) ->
  settings = getSettings(template)
  if confirm('Delete item?')
    if settings.onDelete
      settings.onDelete(createHandlerContext(template))
    else
      _.each Template.tree.getSelectedIds(template.$tree), (id) ->
        collection.remove(id)

####################################################################################################
# AUXILIARY
####################################################################################################

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

getSettings = (arg) ->
  template = getTemplate(arg)
  unless template.settings
    template.settings = _.extend({

    }, template.data.settings)
  template.settings

createHandlerContext = (template, extraArgs) ->
  $tree = template.$tree
  return _.extend({
    selectedIds: Template.tree.getSelectedIds($tree)
    collection: template.collection
  }, extraArgs)

####################################################################################################
# API
####################################################################################################

_.extend(TemplateClass, {
  getTemplate: getTemplate
  getSettings: getSettings
})
