import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:blog/services/auth_service.dart';

class EditPostPage extends StatefulWidget {
  final Map<String, dynamic> post;

  const EditPostPage({
    super.key,
    required this.post,
  });

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  // Existing images currently belonging to the post.
  final List<Map<String, dynamic>> _existingImages = [];

  // Existing images selected by admin for deletion.
  final List<Map<String, dynamic>> _imagesToDelete = [];

  // Newly selected images.
  final List<PlatformFile> _newImages = [];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.post['title']?.toString() ?? '',
    );

    _descriptionController = TextEditingController(
      text: widget.post['description']?.toString() ?? '',
    );

    _loadImages();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  // ==========================================================
  // LOAD EXISTING IMAGES
  // ==========================================================

  Future<void> _loadImages() async {
    try {
      final response = await _supabase
          .from('post-images')
          .select('id, post_id, image')
          .eq('post_id', widget.post['id'])
          .order('id', ascending: true);

      final List<Map<String, dynamic>> images = (response as List)
          .map((image) => Map<String, dynamic>.from(image))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _existingImages.clear();
        _existingImages.addAll(images);
        _isLoading = false;
      });
    } on PostgrestException catch (e) {
      debugPrint('LOAD EDIT IMAGES ERROR');
      debugPrint('Message: ${e.message}');
      debugPrint('Code: ${e.code}');
      debugPrint('Details: ${e.details}');
      debugPrint('Hint: ${e.hint}');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load images: ${e.message}',
          ),
        ),
      );
    } catch (e) {
      debugPrint('LOAD EDIT IMAGES ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load images: $e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // PICK NEW IMAGES
  // ==========================================================

  Future<void> _pickImages() async {
    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );

      if (result == null) {
        return;
      }

      final List<PlatformFile> selectedImages = result.files
          .where(
            (file) =>
                file.bytes != null &&
                file.bytes!.isNotEmpty,
          )
          .toList();

      if (selectedImages.isEmpty) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _newImages.addAll(selectedImages);
      });
    } catch (e) {
      debugPrint('PICK IMAGES ERROR: $e');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to select images: $e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // REMOVE EXISTING IMAGE FROM EDIT LIST
  //
  // This does NOT immediately delete it from Supabase.
  //
  // It is only marked for deletion.
  // Actual deletion happens when Save is pressed.
  // ==========================================================

  void _removeExistingImage(
    Map<String, dynamic> image,
  ) {
    setState(() {
      _existingImages.removeWhere(
        (item) =>
            item['id'].toString() ==
            image['id'].toString(),
      );

      _imagesToDelete.add(image);
    });
  }

  // ==========================================================
  // RESTORE EXISTING IMAGE
  // ==========================================================

  void _restoreExistingImage(
    Map<String, dynamic> image,
  ) {
    setState(() {
      _imagesToDelete.removeWhere(
        (item) =>
            item['id'].toString() ==
            image['id'].toString(),
      );

      _existingImages.add(image);

      _existingImages.sort(
        (a, b) {
          final int aId =
              int.tryParse(a['id'].toString()) ?? 0;

          final int bId =
              int.tryParse(b['id'].toString()) ?? 0;

          return aId.compareTo(bId);
        },
      );
    });
  }

  // ==========================================================
  // REMOVE NEW IMAGE
  // ==========================================================

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  // ==========================================================
  // GET STORAGE PATH
  //
  // Example:
  //
  // https://xxxxx.supabase.co/storage/v1/object/public/
  // upload-posts-images/posts/123/image.jpg
  //
  // returns:
  //
  // posts/123/image.jpg
  // ==========================================================

  String? _getStoragePath(String imageUrl) {
    try {
      final Uri uri = Uri.parse(imageUrl);

      final String path = uri.path;

      const String marker =
          '/storage/v1/object/public/upload_posts_images/';

      final int index = path.indexOf(marker);

      if (index == -1) {
        debugPrint(
          'Could not determine storage path:',
        );

        debugPrint(imageUrl);

        return null;
      }

      final String storagePath =
          path.substring(index + marker.length);

      if (storagePath.isEmpty) {
        return null;
      }

      return Uri.decodeComponent(storagePath);
    } catch (e) {
      debugPrint(
        'GET STORAGE PATH ERROR: $e',
      );

      return null;
    }
  }

  // ==========================================================
  // DELETE STORAGE IMAGE
  // ==========================================================

  Future<void> _deleteStorageImage(
    String imageUrl,
  ) async {
    final String? storagePath =
        _getStoragePath(imageUrl);

    if (storagePath == null ||
        storagePath.isEmpty) {
      return;
    }

    try {
      await _supabase.storage
          .from('upload_posts_images')
          .remove([storagePath]);

      debugPrint(
        'Deleted storage file: $storagePath',
      );
    } catch (e) {
      debugPrint(
        'STORAGE DELETE WARNING: $e',
      );

      // We don't stop the entire update if
      // the storage file cannot be deleted.
    }
  }

  // ==========================================================
  // GENERATE UNIQUE FILE PATH
  // ==========================================================

  String _generateStoragePath(
    dynamic postId,
    PlatformFile file,
  ) {
    final String originalName =
        file.name.trim();

    final String extension =
        originalName.contains('.')
            ? originalName
                .split('.')
                .last
                .toLowerCase()
            : 'jpg';

    final int timestamp =
        DateTime.now().millisecondsSinceEpoch;

    return 'posts/$postId/$timestamp.$extension';
  }

  // ==========================================================
  // UPLOAD NEW IMAGE
  // ==========================================================

  Future<String> _uploadImage(
    dynamic postId,
    PlatformFile file,
  ) async {
    final Uint8List bytes = file.bytes!;

    final String storagePath =
        _generateStoragePath(
      postId,
      file,
    );

    await _supabase.storage
        .from('upload_posts_images')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: false,
          ),
        );

    final String publicUrl =
        _supabase.storage
            .from('upload_posts_images')
            .getPublicUrl(storagePath);

    return publicUrl;
  }

  // ==========================================================
  // VALIDATE
  // ==========================================================

  bool _validate() {
    final String title =
        _titleController.text.trim();

    final String description =
        _descriptionController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a title.',
          ),
        ),
      );

      return false;
    }

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a description.',
          ),
        ),
      );

      return false;
    }

    // At least one image must remain.
    if (_existingImages.isEmpty &&
        _newImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A post must have at least one image.',
          ),
        ),
      );

      return false;
    }

    return true;
  }

  // ==========================================================
  // SAVE CHANGES
  // ==========================================================

  Future<void> _saveChanges() async {
    if (_isSaving) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (!_validate()) {
      return;
    }

    final dynamic postId =
        widget.post['id'];

    final String title =
        _titleController.text.trim();

    final String description =
        _descriptionController.text.trim();

    setState(() {
      _isSaving = true;
    });

    try {
      debugPrint(
        '======================================',
      );

      debugPrint(
        'EDIT POST',
      );

      debugPrint(
        'Post ID: $postId',
      );

      debugPrint(
        'Existing images remaining: '
        '${_existingImages.length}',
      );

      debugPrint(
        'Images to delete: '
        '${_imagesToDelete.length}',
      );

      debugPrint(
        'New images: '
        '${_newImages.length}',
      );

      debugPrint(
        '======================================',
      );

      // ======================================================
      // STEP 1
      // UPDATE POST
      // ======================================================

      await _supabase
          .from('posts')
          .update({
        'title': title,
        'description': description,
      }).eq(
        'id',
        postId,
      );

      debugPrint(
        'Post information updated.',
      );

      // ======================================================
      // STEP 2
      // DELETE REMOVED IMAGES
      //
      // Comments are deleted first because comments
      // reference image_id.
      // ======================================================

      for (final image
          in _imagesToDelete) {
        final dynamic imageId =
            image['id'];

        final String imageUrl =
            image['image']
                ?.toString() ??
            '';

        // -----------------------------------------------
        // Delete comments
        // -----------------------------------------------

        await _supabase
            .from('comments')
            .delete()
            .eq(
              'image_id',
              imageId,
            );

        // -----------------------------------------------
        // Delete storage image
        // -----------------------------------------------

        if (imageUrl.isNotEmpty) {
          await _deleteStorageImage(
            imageUrl,
          );
        }

        // -----------------------------------------------
        // Delete image database record
        // -----------------------------------------------

        await _supabase
            .from('post-images')
            .delete()
            .eq(
              'id',
              imageId,
            );

        debugPrint(
          'Removed image ID: $imageId',
        );
      }

      // ======================================================
      // STEP 3
      // UPLOAD NEW IMAGES
      // ======================================================

      for (final PlatformFile file
          in _newImages) {
        try {
          final String imageUrl =
              await _uploadImage(
            postId,
            file,
          );

          await _supabase
              .from('post-images')
              .insert({
            'post_id': postId,
            'image': imageUrl,
          });

          debugPrint(
            'Uploaded: ${file.name}',
          );
        } catch (uploadError) {
          debugPrint(
            'UPLOAD ERROR: $uploadError',
          );

          throw Exception(
            'Failed to upload ${file.name}: '
            '$uploadError',
          );
        }
      }

      // ======================================================
      // STEP 4
      // UPDATE LOCAL POST
      // ======================================================

      widget.post['title'] = title;
      widget.post['description'] =
          description;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Post updated successfully.',
          ),
        ),
      );

      // Give the previous page a signal that
      // the post was successfully updated.
      Navigator.pop(
        context,
        true,
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '======================================',
      );

      debugPrint(
        'EDIT POST SUPABASE ERROR',
      );

      debugPrint(
        'Message: ${e.message}',
      );

      debugPrint(
        'Code: ${e.code}',
      );

      debugPrint(
        'Details: ${e.details}',
      );

      debugPrint(
        'Hint: ${e.hint}',
      );

      debugPrint(
        '======================================',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to update post: '
            '${e.message}',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'EDIT POST ERROR: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to update post: $e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // CONFIRM REMOVE EXISTING IMAGE
  // ==========================================================

  Future<void> _confirmRemoveExistingImage(
    Map<String, dynamic> image,
  ) async {
    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Remove Image',
          ),
          content: const Text(
            'This image will be removed from '
            'the post when you save the changes.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.red,
                foregroundColor:
                    Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'Remove',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _removeExistingImage(image);
    }
  }

  // ==========================================================
  // BUILD EXISTING IMAGE
  // ==========================================================

  Widget _buildExistingImage(
    Map<String, dynamic> image,
    int index,
  ) {
    final String imageUrl =
        image['image']?.toString() ??
            '';

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder:
                  (
                    context,
                    child,
                    loadingProgress,
                  ) {
                if (loadingProgress ==
                    null) {
                  return child;
                }

                return const Center(
                  child:
                      CircularProgressIndicator(),
                );
              },
              errorBuilder:
                  (
                    context,
                    error,
                    stackTrace,
                  ) {
                return const Center(
                  child: Icon(
                    Icons.broken_image,
                    size: 40,
                  ),
                );
              },
            ),
          ),
        ),

        // Image number
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius:
                  BorderRadius.circular(8),
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

        // Remove button
        Positioned(
          right: 6,
          top: 6,
          child: Material(
            color: Colors.red,
            shape:
                const CircleBorder(),
            child: InkWell(
              customBorder:
                  const CircleBorder(),
              onTap: () {
                _confirmRemoveExistingImage(
                  image,
                );
              },
              child: const Padding(
                padding:
                    EdgeInsets.all(6),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // BUILD NEW IMAGE
  // ==========================================================

  Widget _buildNewImage(
    PlatformFile file,
    int index,
  ) {
    final Uint8List bytes =
        file.bytes!;

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
            ),
          ),
        ),

        // NEW label
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius:
                  BorderRadius.circular(8),
            ),
            child: const Text(
              'NEW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ),

        // Remove button
        Positioned(
          right: 6,
          top: 6,
          child: Material(
            color: Colors.red,
            shape:
                const CircleBorder(),
            child: InkWell(
              customBorder:
                  const CircleBorder(),
              onTap: () {
                _removeNewImage(index);
              },
              child: const Padding(
                padding:
                    EdgeInsets.all(6),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // RESTORE DELETED IMAGE LIST
  // ==========================================================

  Widget _buildDeletedImages() {
    if (_imagesToDelete.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),

        const Text(
          'Images marked for removal',
          style: TextStyle(
            fontSize: 16,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection:
                Axis.horizontal,
            itemCount:
                _imagesToDelete.length,
            separatorBuilder:
                (context, index) =>
                    const SizedBox(
              width: 10,
            ),
            itemBuilder:
                (context, index) {
              final image =
                  _imagesToDelete[
                      index];

              final String url =
                  image['image']
                          ?.toString() ??
                      '';

              return SizedBox(
                width: 100,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.45,
                        child:
                            ClipRRect(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                          child:
                              Image.network(
                            url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),

                    Positioned.fill(
                      child: Container(
                        decoration:
                            BoxDecoration(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                          color:
                              Colors.red
                                  .withOpacity(
                            0.25,
                          ),
                        ),
                        alignment:
                            Alignment.center,
                        child:
                            const Icon(
                          Icons.delete,
                          color:
                              Colors.red,
                          size: 30,
                        ),
                      ),
                    ),

                    Positioned(
                      right: 4,
                      top: 4,
                      child:
                          Material(
                        color:
                            Colors.green,
                        shape:
                            const CircleBorder(),
                        child:
                            InkWell(
                          customBorder:
                              const CircleBorder(),
                          onTap: () {
                            _restoreExistingImage(
                              image,
                            );
                          },
                          child:
                              const Padding(
                            padding:
                                EdgeInsets.all(
                              5,
                            ),
                            child:
                                Icon(
                              Icons
                                  .restore,
                              color: Colors
                                  .white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final int totalImages =
        _existingImages.length +
            _newImages.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Post',
        ),
      ),

      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child:
                        SingleChildScrollView(
                      padding:
                          const EdgeInsets
                              .all(
                        16,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          // ==================================
                          // TITLE
                          // ==================================

                          const Text(
                            'Title',
                            style:
                                TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),

                          const SizedBox(
                            height: 8,
                          ),

                          TextField(
                            controller:
                                _titleController,
                            textInputAction:
                                TextInputAction
                                    .next,
                            decoration:
                                const InputDecoration(
                              hintText:
                                  'Enter post title',
                              border:
                                  OutlineInputBorder(),
                            ),
                          ),

                          const SizedBox(
                            height: 20,
                          ),

                          // ==================================
                          // DESCRIPTION
                          // ==================================

                          const Text(
                            'Description',
                            style:
                                TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),

                          const SizedBox(
                            height: 8,
                          ),

                          TextField(
                            controller:
                                _descriptionController,
                            maxLines: 6,
                            decoration:
                                const InputDecoration(
                              hintText:
                                  'Enter post description',
                              border:
                                  OutlineInputBorder(),
                            ),
                          ),

                          const SizedBox(
                            height: 24,
                          ),

                          // ==================================
                          // IMAGE HEADER
                          // ==================================

                          Row(
                            children: [
                              const Expanded(
                                child:
                                    Text(
                                  'Post Images',
                                  style:
                                      TextStyle(
                                    fontSize:
                                        16,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),
                              ),

                              Text(
                                '$totalImages image${totalImages == 1 ? '' : 's'}',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.grey,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 6,
                          ),

                          const Text(
                            'Remove existing photos or add new photos.',
                            style:
                                TextStyle(
                              color:
                                  Colors.grey,
                            ),
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          // ==================================
                          // ADD IMAGE BUTTON
                          // ==================================

                          SizedBox(
                            width:
                                double.infinity,
                            child:
                                OutlinedButton.icon(
                              onPressed:
                                  _isSaving
                                      ? null
                                      : _pickImages,
                              icon:
                                  const Icon(
                                Icons
                                    .add_photo_alternate_outlined,
                              ),
                              label:
                                  const Text(
                                'Add Photos',
                              ),
                              style:
                                  OutlinedButton
                                      .styleFrom(
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  vertical:
                                      14,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          // ==================================
                          // EXISTING IMAGES
                          // ==================================

                          if (_existingImages
                              .isNotEmpty)
                            GridView.builder(
                              shrinkWrap:
                                  true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              itemCount:
                                  _existingImages
                                      .length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    2,
                                crossAxisSpacing:
                                    10,
                                mainAxisSpacing:
                                    10,
                                childAspectRatio:
                                    1,
                              ),
                              itemBuilder:
                                  (
                                context,
                                index,
                              ) {
                                return _buildExistingImage(
                                  _existingImages[
                                      index],
                                  index,
                                );
                              },
                            )
                          else
                            Container(
                              width:
                                  double.infinity,
                              padding:
                                  const EdgeInsets
                                      .all(
                                24,
                              ),
                              decoration:
                                  BoxDecoration(
                                color: Colors
                                    .grey
                                    .shade100,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  12,
                                ),
                                border:
                                    Border.all(
                                  color: Colors
                                      .grey
                                      .shade300,
                                ),
                              ),
                              child:
                                  const Column(
                                children: [
                                  Icon(
                                    Icons
                                        .image_not_supported_outlined,
                                    size: 45,
                                    color: Colors
                                        .grey,
                                  ),
                                  SizedBox(
                                    height: 8,
                                  ),
                                  Text(
                                    'No existing images',
                                    style:
                                        TextStyle(
                                      color:
                                          Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // ==================================
                          // NEW IMAGES
                          // ==================================

                          if (_newImages
                              .isNotEmpty) ...[
                            const SizedBox(
                              height: 24,
                            ),

                            const Text(
                              'New Photos',
                              style:
                                  TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),

                            const SizedBox(
                              height: 10,
                            ),

                            GridView.builder(
                              shrinkWrap:
                                  true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              itemCount:
                                  _newImages
                                      .length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    2,
                                crossAxisSpacing:
                                    10,
                                mainAxisSpacing:
                                    10,
                                childAspectRatio:
                                    1,
                              ),
                              itemBuilder:
                                  (
                                context,
                                index,
                              ) {
                                return _buildNewImage(
                                  _newImages[
                                      index],
                                  index,
                                );
                              },
                            ),
                          ],

                          // ==================================
                          // DELETED IMAGES
                          // ==================================

                          _buildDeletedImages(),

                          const SizedBox(
                            height: 24,
                          ),

                          // ==================================
                          // INFO
                          // ==================================

                          Container(
                            width:
                                double.infinity,
                            padding:
                                const EdgeInsets
                                    .all(
                              12,
                            ),
                            decoration:
                                BoxDecoration(
                              color: Colors
                                  .deepPurple
                                  .withOpacity(
                                0.08,
                              ),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                12,
                              ),
                            ),
                            child:
                                const Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Icon(
                                  Icons
                                      .info_outline,
                                  color: Colors
                                      .deepPurple,
                                ),
                                SizedBox(
                                  width: 10,
                                ),
                                Expanded(
                                  child: Text(
                                    'Changes are applied when you press Save Changes. '
                                    'Removed photos and their comments will be deleted.',
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(
                            height: 30,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ==========================================
                  // SAVE BUTTON
                  // ==========================================

                  Container(
                    padding:
                        const EdgeInsets
                            .fromLTRB(
                      16,
                      10,
                      16,
                      16,
                    ),
                    decoration:
                        BoxDecoration(
                      color: Theme.of(
                        context,
                      ).scaffoldBackgroundColor,
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 8,
                          color: Colors.black12,
                        ),
                      ],
                    ),
                    child:
                        SizedBox(
                      width:
                          double.infinity,
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            _isSaving
                                ? null
                                : _saveChanges,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                ),
                              )
                            : const Icon(
                                Icons
                                    .save_outlined,
                              ),
                        label: Text(
                          _isSaving
                              ? 'Saving...'
                              : 'Save Changes',
                        ),
                        style:
                            ElevatedButton
                                .styleFrom(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

