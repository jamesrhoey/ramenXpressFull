import 'package:flutter/material.dart';

class ReviewDialog extends StatefulWidget {
  final Function(int rating, String comment) onSubmit;
  final VoidCallback onCancel;

  const ReviewDialog({
    Key? key,
    required this.onSubmit,
    required this.onCancel,
  }) : super(key: key);

  @override
  _ReviewDialogState createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return GestureDetector(
          onTap: () {
            setState(() {
              _rating = index + 1;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(2),
            child: Icon(
              index < _rating ? Icons.star : Icons.star_border,
              color: index < _rating ? Colors.amber : Colors.grey,
              size: 32,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: const Row(
        children: [
          Icon(Icons.star, color: Colors.amber, size: 24),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Rate Your Order',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'How was your experience?',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _buildStarRating(),
            if (_rating > 0) ...[
              const SizedBox(height: 8),
              Text(
                _getRatingText(_rating),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: _getRatingColor(_rating),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Tell us about your experience (optional)',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
                isDense: true,
              ),
              maxLines: 2,
              maxLength: 150,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: _rating > 0
              ? () {
                  widget.onSubmit(_rating, _commentController.text.trim());
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD32D43),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Submit Review'),
        ),
      ],
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }

  Color _getRatingColor(int rating) {
    switch (rating) {
      case 1:
      case 2:
        return Colors.red;
      case 3:
        return Colors.orange;
      case 4:
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
