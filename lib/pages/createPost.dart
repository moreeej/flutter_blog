import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blog/services/auth_service.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController =
      TextEditingController();

  bool _isUploading = false;
  bool _isCreatingPost = false;

  String? _uploadedImageUrl;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    try {
      setState(() {
        _isUploading = true;
      });

      // Pick image from local computer/device
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) {
          setState(() {
            _isUploading = false;
          });
        }
        return;
      }

      final PlatformFile file = result.files.first;

      // Important for Flutter Web
      if (file.bytes == null) {
        throw Exception(
          'Could not read the selected image. Please try another image.',
        );
      }

      // Get extension
      final String extension =
          (file.extension ?? 'jpg').toLowerCase();

      // Generate unique filename
      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Put images inside a folder
      final String filePath = 'posts/$fileName';

      // Correct MIME type
      String contentType;

      switch (extension) {
        case 'jpg':
        case 'jpeg':
          contentType = 'image/jpeg';
          break;

        case 'png':
          contentType = 'image/png';
          break;

        case 'gif':
          contentType = 'image/gif';
          break;

        case 'webp':
          contentType = 'image/webp';
          break;

        case 'bmp':
          contentType = 'image/bmp';
          break;

        default:
          contentType = 'application/octet-stream';
      }

      final supabase = Supabase.instance.client;

      // Upload image to Supabase Storage
      await supabase.storage.from('posts').uploadBinary(
        filePath,
        file.bytes!,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: true,
        ),
      );

      // Get public URL
      final String publicUrl = supabase.storage
          .from('posts')
          .getPublicUrl(filePath);

      if (!mounted) return;

      setState(() {
        _uploadedImageUrl = publicUrl;
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image uploaded successfully!'),
        ),
      );
    } on StorageException catch (e) {
      if (!mounted) return;

      setState(() {
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Supabase Storage error: ${e.message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
        ),
      );
    }
  }

  Future<void> _submitPost() async {
    final String title = _titleController.text.trim();
    final String description = _descriptionController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title'),
        ),
      );
      return;
    }

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a description'),
        ),
      );
      return;
    }

    if (_uploadedImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload an image first'),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isCreatingPost = true;
      });

      final supabase = Supabase.instance.client;

      final user = currentUser;

      if (user == null) {
        throw Exception('You must be logged in to create a post.');
      }

      // Insert post into your Supabase database
      await supabase.from('posts').insert({
        'title': title,
        'description': description,
        'image': _uploadedImageUrl,
        'user_id': user['id'],
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post created successfully!'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create post: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingPost = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TITLE
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // DESCRIPTION
            TextField(
              controller: _descriptionController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // UPLOAD BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _isUploading ? null : _pickAndUploadImage,
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.upload),
                label: Text(
                  _isUploading
                      ? 'Uploading...'
                      : 'Select Image',
                ),
              ),
            ),

            const SizedBox(height: 16),

            // IMAGE PREVIEW
            if (_uploadedImageUrl != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Uploaded image:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _uploadedImageUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) {
                        return Container(
                          height: 200,
                          width: double.infinity,
                          alignment: Alignment.center,
                          color: Colors.grey.shade200,
                          child: const Text(
                            'Unable to display image',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            // CREATE POST BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    _isCreatingPost ? null : _submitPost,
                child: _isCreatingPost
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Create Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}