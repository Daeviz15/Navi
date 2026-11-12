/// Embedded styles: keep roads and transit context, quiet commercial clutter.
/// Native Google attribution is owned by the SDK and remains visible.
const naviDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#101113"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#b8b5ab"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#101113"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#19231e"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#30302c"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#171816"}]},
  {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#484435"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#806b32"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#e0cd93"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#323c45"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0b2030"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#7194a7"}]}
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
