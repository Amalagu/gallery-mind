// GalleryImage is the UI-friendly image model used by Flutter screens.
// Native Android indexing returns IndexedImageRecord objects, then HomePage
// converts them into GalleryImage objects for display.
class GalleryImage {
  const GalleryImage({
    required this.id,
    required this.assetPath,
    required this.title,
    required this.description,
    required this.date,
    required this.location,
    required this.tags,
    this.dateTakenMillis,
    this.matchPercent = 92,
  });

  final String id;
  // assetPath can be either a bundled asset path such as assets/images/img1.jpg
  // or an Android content:// URI for a real gallery photo.
  final String assetPath;
  final String title;
  final String description;
  final String date;
  final String location;
  final List<String> tags;
  // Real gallery images use dateTakenMillis for date grouping. Sample images
  // leave it null and rely on the human-readable date string.
  final int? dateTakenMillis;
  // A display-only percentage used for semantic search/similar-image badges.
  final int matchPercent;
}
