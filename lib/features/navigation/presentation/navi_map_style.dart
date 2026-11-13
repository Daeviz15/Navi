/// Embedded styles: keep roads and transit context, quiet commercial clutter.
/// Native Google attribution is owned by the SDK and remains visible.
const naviDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#101214"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#939A9F"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#101214"},{"weight":3}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#252A2D"}]},
  {"featureType":"administrative","elementType":"labels.text.fill","stylers":[{"color":"#777F85"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.text","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#15201B"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#343A3C"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#15191B"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#A4AAAC"}]},
  {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#514C3C"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#776233"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#E0CA8F"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#293942"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#8CB9D2"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#102733"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#608B9F"}]}
]
''';

const naviLightMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#edeae1"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#59584f"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f6f4ed"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#dce4d7"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#fffdf7"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#d9d4c6"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#d9bc63"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#6b561c"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#c9d1d4"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c3d8e1"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4f7385"}]}
]
''';
