import 'package:flutter_test/flutter_test.dart';
import 'package:gallerymind/services/embedding_index.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes Android ONNX text search bridge', (tester) async {
    final index = EmbeddingIndex();

    await index.initializeTextSearch();
    final count = await index.count();
    expect(count, isNonNegative);
  });
}
