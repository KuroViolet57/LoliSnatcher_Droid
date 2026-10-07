/// Whether the bottom info sheet should build the tag view.
///
/// The sheet's scrollable has to stay mounted while the sheet is shut, or
/// opening it does nothing. The tag view loads the post as soon as it is
/// created, so a shut sheet must not build it.
bool infoSheetShowsTags(double extent) => extent > 0;
