import 'package:flutter_test/flutter_test.dart';
import 'package:gallerymind/data/sample_gallery.dart';
import 'package:gallerymind/services/embedding_index.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('indexes bundled images and searches with Android ONNX',
      (tester) async {
    final index = EmbeddingIndex();

    await index.clear();
    expect(await index.count(), 0);

    final inputs = sampleGalleryImages.take(3).map(
          (image) => IndexedImageInput(
            id: image.id,
            uri: image.assetPath,
            assetPath: image.assetPath,
            title: image.title,
            description: image.description,
            tags: image.tags,
          ),
        );

    await index.indexImages(inputs);
    expect(await index.count(), 3);

    final textResults = await index.searchText('orange sports car', limit: 3);
    expect(textResults, isNotEmpty);
    expect(
      textResults.map((result) => result.record.id),
      contains('orange-car'),
    );
    expect(textResults.first.combinedScore.isFinite, isTrue);

    final imageResults = await index.findSimilarImages(
      'orange-car',
      threshold: -1,
      limit: 3,
    );
    expect(imageResults, isNotEmpty);
    expect(
      imageResults.every((result) => result.record.id != 'orange-car'),
      isTrue,
    );
    expect(imageResults.first.combinedScore.isFinite, isTrue);
  });
}
