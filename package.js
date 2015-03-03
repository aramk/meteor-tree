// Meteor package definition.
Package.describe({
  name: 'aramk:tree',
  version: '0.2.0',
  summary: 'A tree widget for displaying a collection of items in Meteor.',
  git: 'https://github.com/aramk/meteor-tree.git'
});

Package.onUse(function (api) {
  api.versionsFrom('METEOR@1.0');
  api.use([
    'coffeescript',
    'underscore',
    'jquery',
    'less',
    'templating',
    'reactive-var@1.0.4',
    'aramk:utility@0.5.2',
    'aramk:jqtree@1.0.0'
  ], 'client');
  api.use([
    // Used for calling CRUD routes.
    'iron:router@1.0.7',
    // This is weak to allow using other UI frameworks if necessary.
    'nooitaf:semantic-ui@1.7.3'
  ], 'client', {weak: true});
  api.addFiles([
    'src/tree.html',
    'src/tree.coffee',
    'src/tree.less',
    'src/crudTree.html',
    'src/crudTree.coffee'
  ], 'client');
  api.export([
    'TreeModel'
  ], 'client');
});
