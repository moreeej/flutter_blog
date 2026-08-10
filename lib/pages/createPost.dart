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
  final TextEditingController _titleController =
      TextEditingController();

  final TextEditingController _descriptionController =
      TextEditingController();

  bool _isUploading = false;
  bool _isCreatingPost = false;

  // Stores uploaded image URLs
  final List<String> _uploadedImageUrls = [];

  // Your actual Supabase Storage bucket
  static const String imageBucket = 'upload_posts_images';

  // Your actual database tables
  static const String postsTable = 'posts';
  static const String postImagesTable = 'post-images';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ==========================================================
  // PICK AND UPLOAD MULTIPLE IMAGES
  // ==========================================================

  Future<void> _pickAndUploadImages() async {
    try {
      setState(() {
        _isUploading = true;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
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

      // Maximum 10 images per post
      if (result.files.length > 10) {
        if (mounted) {
          setState(() {
            _isUploading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You can select a maximum of 10 images.',
              ),
            ),
          );
        }

        return;
      }

      // Prevent total images from exceeding 10
      if (_uploadedImageUrls.length + result.files.length > 10) {
        if (mounted) {
          setState(() {
            _isUploading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A post can have a maximum of 10 images.',
              ),
            ),
          );
        }

        return;
      }

      final SupabaseClient supabase =
          Supabase.instance.client;

      final List<String> uploadedUrls = [];

      // ========================================================
      // UPLOAD EACH IMAGE
      // ========================================================

      for (final PlatformFile file in result.files) {
        if (file.bytes == null) {
          continue;
        }

        final String extension =
            (file.extension ?? 'jpg').toLowerCase();

        // Unique filename
        final String timestamp =
            DateTime.now()
                .microsecondsSinceEpoch
                .toString();

        final String fileName =
            '${timestamp}_${file.name}';

        // Folder inside upload_posts_images bucket
        final String filePath =
            'posts/$fileName';

        // ======================================================
        // DETERMINE CONTENT TYPE
        // ======================================================

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

        // ======================================================
        // UPLOAD TO YOUR ACTUAL BUCKET
        // ======================================================

        await supabase.storage
            .from(imageBucket)
            .uploadBinary(
              filePath,
              file.bytes!,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: false,
              ),
            );

        // ======================================================
        // GET PUBLIC URL
        // ======================================================

        final String publicUrl =
            supabase.storage
                .from(imageBucket)
                .getPublicUrl(filePath);

        uploadedUrls.add(publicUrl);
      }

      if (!mounted) return;

      setState(() {
        _uploadedImageUrls.addAll(uploadedUrls);
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${uploadedUrls.length} image(s) uploaded successfully!',
          ),
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
          content: Text(
            'Upload failed: $e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // REMOVE IMAGE
  // ==========================================================

  void _removeImage(int index) {
    setState(() {
      _uploadedImageUrls.removeAt(index);
    });
  }

  // ==========================================================
  // CREATE POST
  // ==========================================================

  Future<void> _submitPost() async {
    final String title =
        _titleController.text.trim();

    final String description =
        _descriptionController.text.trim();

    // ========================================================
    // VALIDATION
    // ========================================================

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a title.',
          ),
        ),
      );
      return;
    }

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a description.',
          ),
        ),
      );
      return;
    }

    if (_uploadedImageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please upload at least one image.',
          ),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isCreatingPost = true;
      });

      final SupabaseClient supabase =
          Supabase.instance.client;

      // ========================================================
      // GET CURRENT USER
      // ========================================================

      final user = currentUser;

      if (user == null) {
        throw Exception(
          'You must be logged in to create a post.',
        );
      }

      // ========================================================
      // STEP 1
      // INSERT INTO "posts"
      //
      // posts:
      // id
      // user_id
      // title
      // description
      // created_at
      //
      // id and created_at are automatically generated.
      // ========================================================

      final Map<String, dynamic> postResponse =
          await supabase
              .from(postsTable)
              .insert({
                'user_id': user['id'],
                'title': title,
                'description': description,
              })
              .select('id')
              .single();

      // Get generated post ID
      final dynamic postId =
          postResponse['id'];

      // ========================================================
      // STEP 2
      // INSERT IMAGES INTO "post-images"
      //
      // post-images:
      // id
      // post_id
      // image
      //
      // id is automatically generated.
      // ========================================================

      final List<Map<String, dynamic>> imageRows =
          _uploadedImageUrls.map((imageUrl) {
        return {
          'post_id': postId,
          'image': imageUrl,
        };
      }).toList();

      await supabase
          .from(postImagesTable)
          .insert(imageRows);

      // ========================================================
      // SUCCESS
      // ========================================================

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Post created successfully!',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to create post: $e',
          ),
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

  // ==========================================================
  // IMAGE PREVIEW
  // ==========================================================

  Widget _buildImagePreview() {
    if (_uploadedImageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selected Images',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        GridView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount:
              _uploadedImageUrls.length,
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final String imageUrl =
                _uploadedImageUrls[index];

            return Stack(
              children: [
                // IMAGE
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) {
                        return Container(
                          color:
                              Colors.grey.shade200,
                          alignment:
                              Alignment.center,
                          child: const Icon(
                            Icons.broken_image,
                            size: 40,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // REMOVE BUTTON
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () {
                      _removeImage(index);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration:
                          const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),

                // IMAGE NUMBER
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration:
                        BoxDecoration(
                      color: Colors.black54,
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Post',
        ),
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            // TITLE
            TextField(
              controller: _titleController,
              textInputAction:
                  TextInputAction.next,
              decoration:
                  const InputDecoration(
                labelText: 'Title',
                hintText:
                    'Enter your post title',
                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // DESCRIPTION
            TextField(
              controller:
                  _descriptionController,
              maxLines: 6,
              decoration:
                  const InputDecoration(
                labelText: 'Description',
                hintText:
                    'Write something...',
                alignLabelWithHint: true,
                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // SELECT IMAGES
            SizedBox(
              width: double.infinity,
              child:
                  ElevatedButton.icon(
                onPressed: _isUploading
                    ? null
                    : _pickAndUploadImages,

                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.photo_library,
                      ),

                label: Text(
                  _isUploading
                      ? 'Uploading...'
                      : 'Select Images',
                ),
              ),
            ),

            const SizedBox(height: 8),

            // IMAGE COUNT
            if (_uploadedImageUrls
                .isNotEmpty)
              Text(
                '${_uploadedImageUrls.length} image(s) selected',
                style: TextStyle(
                  color:
                      Colors.grey.shade700,
                ),
              ),

            const SizedBox(height: 16),

            // IMAGE PREVIEW
            _buildImagePreview(),

            const SizedBox(height: 24),

            // CREATE POST
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    _isCreatingPost ||
                            _isUploading
                        ? null
                        : _submitPost,

                child: _isCreatingPost
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Create Post',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

