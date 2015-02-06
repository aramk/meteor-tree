// Meteor package definition.
Package.describe({
  name: 'aramk:tree',
  version: '0.1.0',
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
    ],'client');
  api.addFiles([
    'src/tree.html',
    'src/tree.coffee'
  ], 'client');
});
