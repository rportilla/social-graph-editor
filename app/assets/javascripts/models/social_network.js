App.SocialNetwork = DS.Model.extend({
  name: DS.attr('string'),
  scale: DS.attr('number', { defaultValue: 1 }),
  translation_x: DS.attr('number', { defaultValue: 0 }),
  translation_y: DS.attr('number', { defaultValue: 0 }),
  nodes: DS.hasMany('App.Node'),
  families: DS.hasMany('App.Family'),

  translationString: function() {
    return this.get('translation_x') + ", " + this.get('translation_y');
  },

  actorFamilies: function() {
    return this.get('families').toArray().map(function (family) {
      if(family.get("kind") == "Actor") {
        return family;
      }
    })
  }.property("families"),

});
