import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DocumentPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> document;
  final Map<String, dynamic> structure;

  const DocumentPreviewDialog({
    Key? key,
    required this.document,
    required this.structure,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final title = document['title'] ?? 'untitled'.tr;

    return AlertDialog(
      title: Text('document_preview'.tr),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // 文档结构
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 结构树
                    _buildStructureTree(context),

                    // 示例块
                    const SizedBox(height: 16),
                    _buildSampleChunks(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('close'.tr),
        ),
      ],
    );
  }

  Widget _buildStructureTree(BuildContext context) {
    if (structure['structure'] == null ||
        (structure['structure'] as List).isEmpty) {
      return Center(
        child: Text('no_structure_available'.tr),
      );
    }

    return _buildStructureList(structure['structure'] as List);
  }

  Widget _buildStructureList(List structureList) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: structureList.length,
      itemBuilder: (context, index) {
        final item = structureList[index];
        return _buildStructureItem(item, 0);
      },
    );
  }

  Widget _buildStructureItem(dynamic item, int level) {
    final title = item['title'] ?? '';
    final number = item['number']?.toString() ?? '';
    final children = item['children'] as List?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: level * 16.0),
          child: Row(
            children: [
              Icon(
                level == 0
                    ? Icons.book
                    : (level == 1 ? Icons.bookmark : Icons.article),
                size: 20 - level * 2,
                color: Colors.blue.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$number $title',
                  style: TextStyle(
                    fontSize: 16.0 - level.toDouble(),
                    fontWeight:
                        level == 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (children != null && children.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: children.length,
            itemBuilder: (context, index) {
              return _buildStructureItem(children[index], level + 1);
            },
          ),
      ],
    );
  }

  // 显示示例块
  Widget _buildSampleChunks(BuildContext context) {
    if (structure['chunks'] == null || (structure['chunks'] as List).isEmpty) {
      return const SizedBox.shrink();
    }

    final chunks = structure['chunks'] as List;
    final sampleChunks = chunks.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'sample_chunks'.tr,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...sampleChunks.map((chunk) {
          final text = chunk['text'] as String? ?? '';
          final truncatedText =
              text.length > 100 ? '${text.substring(0, 100)}...' : text;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(truncatedText),
            ),
          );
        }).toList(),
      ],
    );
  }
}
