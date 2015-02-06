templateName = 'crudTree'
TemplateClass = Template[templateName]
selectEventName = 'select'
checkEventName = 'check'

TemplateClass.created = ->

TemplateClass.rendered = ->

TemplateClass.destory = ->

TemplateClass.events

####################################################################################################
# AUXILIARY
####################################################################################################

getSettings = (arg) ->
  template = getTemplate(arg)
  unless template.settings
    template.settings = _.extend({

    }, template.data.settings)
  template.settings

####################################################################################################
# API
####################################################################################################

_.extend(TemplateClass, {
})
