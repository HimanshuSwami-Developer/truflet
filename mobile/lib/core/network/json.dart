/// The API speaks JSON; screens read fields straight from these maps.
typedef Json = Map<String, dynamic>;

List<Json> asList(dynamic v) => (v as List? ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();

Json asMap(dynamic v) => (v as Map? ?? const {}).cast<String, dynamic>();
