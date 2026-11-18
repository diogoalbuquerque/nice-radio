// Android's `just_audio` never clears its native ICY info on `setUrl`, so the
// *previous* station's title is re-sent with every event of the next one. A
// station that sends no titles (Rádio Justiça after FM O Dia) then looks like
// it is playing the old station's title. `stale` is that leftover title,
// captured when the station was switched; it is ignored until a different
// title arrives. Returns the usable title, or null (absent / blank / stale).
String? freshIcyTitle(String? raw, {String? stale}) {
  final title = raw?.trim();
  if (title == null || title.isEmpty) return null;
  if (stale != null && title == stale) return null;
  return title;
}
