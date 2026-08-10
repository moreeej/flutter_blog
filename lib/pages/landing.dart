import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blog/services/auth_service.dart';

import 'package:blog/pages/createPost.dart';
import 'package:blog/pages/profile.dart';
import 'package:blog/pages/editPost.dart';

void main() {
  runApp(const LandingPage());
}

// ==========================================================
// LANDING PAGE
// ==========================================================

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Landing Page',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LandingScreen(),
    );
  }
}

// ==========================================================
// LANDING SCREEN
// ==========================================================

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ==========================================================
  // PAGINATION
  // ==========================================================

  static const int _pageSize = 5;

  final List<Map<String, dynamic>> _posts = [];

  bool _isLoading = false;
  bool _hasMore = true;

  int _offset = 0;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    _loadPosts();
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    super.dispose();
  }

  // ==========================================================
  // SCROLL PAGINATION
  // ==========================================================

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_isLoading) {
      return;
    }

    if (!_hasMore) {
      return;
    }

    final position = _scrollController.position;

    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadPosts();
    }
  }

  // ==========================================================
  // LOAD POSTS
  // ==========================================================

  Future<void> _loadPosts() async {
    if (_isLoading || !_hasMore) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final int start = _offset;
      final int end = _offset + _pageSize - 1;

      debugPrint('Loading posts from $start to $end');

      // ======================================================
      // GET POSTS
      // ======================================================

      final postsResponse = await _supabase
          .from('posts')
          .select('id, user_id, title, description')
          .order('id', ascending: false)
          .range(start, end);

      final List<Map<String, dynamic>> newPosts = (postsResponse as List)
          .map((post) => Map<String, dynamic>.from(post))
          .toList();

      // ======================================================
      // NO MORE POSTS
      // ======================================================

      if (newPosts.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _hasMore = false;
          _isLoading = false;
        });

        return;
      }

      // ======================================================
      // GET POST IDS
      // ======================================================

      final List<dynamic> postIds = newPosts.map((post) => post['id']).toList();

      // ======================================================
      // GET IMAGES
      // ======================================================

      final imagesResponse = await _supabase
          .from('post-images')
          .select('id, post_id, image')
          .inFilter('post_id', postIds)
          .order('id', ascending: true);

      final List<Map<String, dynamic>> imageRows = (imagesResponse as List)
          .map((image) => Map<String, dynamic>.from(image))
          .toList();

      // ======================================================
      // GET IMAGE IDS
      // ======================================================

      final List<dynamic> imageIds = imageRows
          .map((image) => image['id'])
          .toList();

      // ======================================================
      // GET COMMENTS
      // ======================================================

      List<Map<String, dynamic>> commentRows = [];

      if (imageIds.isNotEmpty) {
        final commentsResponse = await _supabase
            .from('comments')
            .select(
              'id, user_id, image_id, comment, created_at, '
              'users(username, profile_pic)',
            )
            .inFilter('image_id', imageIds)
            .order('created_at', ascending: true);

        commentRows = (commentsResponse as List)
            .map((comment) => Map<String, dynamic>.from(comment))
            .toList();
      }

      // ======================================================
      // GROUP COMMENTS BY IMAGE
      // ======================================================

      final Map<String, List<Map<String, dynamic>>> commentsByImage = {};

      for (final comment in commentRows) {
        final String imageId = comment['image_id'].toString();

        commentsByImage.putIfAbsent(imageId, () => []);

        commentsByImage[imageId]!.add(comment);
      }

      // ======================================================
      // GROUP IMAGES BY POST
      // ======================================================

      final Map<String, List<Map<String, dynamic>>> imagesByPost = {};

      for (final imageRow in imageRows) {
        final dynamic imageId = imageRow['id'];
        final dynamic postId = imageRow['post_id'];

        final String imageUrl = imageRow['image']?.toString() ?? '';

        if (imageUrl.isEmpty) {
          continue;
        }

        final String imageKey = imageId.toString();

        final String postKey = postId.toString();

        final List<Map<String, dynamic>> comments =
            commentsByImage[imageKey] ?? [];

        final Map<String, dynamic> imageData = {
          'id': imageId,
          'post_id': postId,
          'image': imageUrl,
          'comments': comments,
        };

        imagesByPost.putIfAbsent(postKey, () => []).add(imageData);
      }

      // ======================================================
      // ATTACH IMAGES TO POSTS
      // ======================================================

      for (final post in newPosts) {
        final String postKey = post['id'].toString();

        post['images'] = imagesByPost[postKey] ?? <Map<String, dynamic>>[];
      }

      // ======================================================
      // UPDATE STATE
      // ======================================================

      if (!mounted) {
        return;
      }

      setState(() {
        _posts.addAll(newPosts);

        _offset += newPosts.length;

        _hasMore = newPosts.length == _pageSize;

        _isLoading = false;
      });

      debugPrint('Loaded ${newPosts.length} posts');

      debugPrint('Total posts: ${_posts.length}');

      debugPrint('Next offset: $_offset');
    } on PostgrestException catch (e) {
      debugPrint('SUPABASE LOAD POSTS ERROR');

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
        SnackBar(content: Text('Failed to load posts: ${e.message}')),
      );
    } catch (e) {
      debugPrint('LOAD POSTS ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load posts: $e')));
    }
  }

  // ==========================================================
  // REFRESH POSTS
  // ==========================================================

  Future<void> _refreshPosts() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _posts.clear();

      _offset = 0;

      _hasMore = true;

      _isLoading = false;
    });

    await _loadPosts();
  }

  // ==========================================================
  // OPEN IMAGE VIEWER
  // ==========================================================

  void _openImageViewer(List<Map<String, dynamic>> images, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ImageViewerPage(images: images, initialIndex: initialIndex),
      ),
    );
  }

  // ==========================================================
  // BUILD IMAGE COLLAGE
  //
  // Maximum preview = 4 images.
  //
  // If there are more than 4:
  //
  // 1  | 2
  // --------
  // 3  | 4 +N
  //
  // All images are still passed to ImageViewerPage.
  // ==========================================================

  Widget _buildImageCollage(List<Map<String, dynamic>> images) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    final int visibleCount = images.length > 4 ? 4 : images.length;

    // ========================================================
    // ONE IMAGE
    // ========================================================

    if (visibleCount == 1) {
      return SizedBox(
        width: double.infinity,
        height: 260,
        child: GestureDetector(
          onTap: () {
            _openImageViewer(images, 0);
          },
          child: _buildCollageImage(images[0]['image'].toString()),
        ),
      );
    }

    // ========================================================
    // TWO IMAGES
    // ========================================================

    if (visibleCount == 2) {
      return SizedBox(
        width: double.infinity,
        height: 260,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  _openImageViewer(images, 0);
                },
                child: _buildCollageImage(images[0]['image'].toString()),
              ),
            ),

            const SizedBox(width: 2),

            Expanded(
              child: GestureDetector(
                onTap: () {
                  _openImageViewer(images, 1);
                },
                child: _buildCollageImage(images[1]['image'].toString()),
              ),
            ),
          ],
        ),
      );
    }

    // ========================================================
    // THREE IMAGES
    // ========================================================

    if (visibleCount == 3) {
      return SizedBox(
        width: double.infinity,
        height: 260,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () {
                  _openImageViewer(images, 0);
                },
                child: _buildCollageImage(images[0]['image'].toString()),
              ),
            ),

            const SizedBox(width: 2),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _openImageViewer(images, 1);
                      },
                      child: _buildCollageImage(images[1]['image'].toString()),
                    ),
                  ),

                  const SizedBox(height: 2),

                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _openImageViewer(images, 2);
                      },
                      child: _buildCollageImage(images[2]['image'].toString()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ========================================================
    // FOUR OR MORE IMAGES
    // ========================================================

    final int remainingImages = images.length - 4;

    return SizedBox(
      width: double.infinity,
      height: 260,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ====================================================
          // LEFT
          // ====================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _openImageViewer(images, 0);
                    },
                    child: _buildCollageImage(images[0]['image'].toString()),
                  ),
                ),

                const SizedBox(height: 2),

                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _openImageViewer(images, 2);
                    },
                    child: _buildCollageImage(images[2]['image'].toString()),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 2),

          // ====================================================
          // RIGHT
          // ====================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _openImageViewer(images, 1);
                    },
                    child: _buildCollageImage(images[1]['image'].toString()),
                  ),
                ),

                const SizedBox(height: 2),

                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // IMPORTANT:
                      // Opens the full image list.
                      //
                      // If there are 7 images,
                      // initial page = image 4,
                      // and the user can swipe to
                      // images 5, 6, and 7.
                      _openImageViewer(images, 3);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCollageImage(images[3]['image'].toString()),

                        if (remainingImages > 0)
                          Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            child: Text(
                              '+$remainingImages',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SINGLE COLLAGE IMAGE
  // ==========================================================

  Widget _buildCollageImage(String imageUrl) {
    return SizedBox.expand(
      child: Container(
        color: Colors.grey.shade200,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,

          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }

            return const Center(child: CircularProgressIndicator());
          },

          errorBuilder: (context, error, stackTrace) {
            return const Center(child: Icon(Icons.broken_image, size: 50));
          },
        ),
      ),
    );
  }

  // ==========================================================
  // GET STORAGE PATH FROM IMAGE URL
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

      const String marker = '/storage/v1/object/public/upload-posts-images/';

      final int index = path.indexOf(marker);

      if (index == -1) {
        debugPrint('Could not determine storage path: $imageUrl');

        return null;
      }

      final String storagePath = path.substring(index + marker.length);

      if (storagePath.isEmpty) {
        return null;
      }

      return Uri.decodeComponent(storagePath);
    } catch (e) {
      debugPrint('Storage path error: $e');

      return null;
    }
  }

  // ==========================================================
  // DELETE POST
  //
  // Deletes:
  //
  // 1. Comments
  // 2. Image records
  // 3. Actual Storage images
  // 4. Post
  // ==========================================================

  Future<void> _deletePost(dynamic postId) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Post'),

          content: const Text(
            'Are you sure you want to delete this post?\n\n'
            'All images and comments attached '
            'to this post will also be deleted.',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('======================================');

      debugPrint('DELETE POST');

      debugPrint('Post ID: $postId');

      debugPrint('======================================');

      // ======================================================
      // STEP 1
      // GET IMAGE RECORDS
      // ======================================================

      final imageResponse = await _supabase
          .from('post-images')
          .select('id, image')
          .eq('post_id', postId);

      final List<Map<String, dynamic>> imageRows = (imageResponse as List)
          .map((image) => Map<String, dynamic>.from(image))
          .toList();

      final List<dynamic> imageIds = imageRows
          .map((image) => image['id'])
          .toList();

      debugPrint('Image IDs: $imageIds');

      // ======================================================
      // STEP 2
      // GET STORAGE FILE PATHS
      // ======================================================

      final List<String> storagePaths = [];

      for (final imageRow in imageRows) {
        final String imageUrl = imageRow['image']?.toString() ?? '';

        if (imageUrl.isEmpty) {
          continue;
        }

        final String? storagePath = _getStoragePath(imageUrl);

        if (storagePath != null && storagePath.isNotEmpty) {
          storagePaths.add(storagePath);
        }
      }

      debugPrint('Storage files: $storagePaths');

      // ======================================================
      // STEP 3
      // DELETE COMMENTS
      // ======================================================

      if (imageIds.isNotEmpty) {
        await _supabase
            .from('comments')
            .delete()
            .inFilter('image_id', imageIds);

        debugPrint('Comments deleted.');
      }

      // ======================================================
      // STEP 4
      // DELETE ACTUAL STORAGE FILES
      // ======================================================

      if (storagePaths.isNotEmpty) {
        try {
          await _supabase.storage
              .from('upload-posts-images')
              .remove(storagePaths);

          debugPrint('Storage images deleted.');
        } catch (storageError) {
          debugPrint(
            'Storage delete warning: '
            '$storageError',
          );

          // We continue because the database
          // records should still be removed.
        }
      }

      // ======================================================
      // STEP 5
      // DELETE IMAGE RECORDS
      // ======================================================

      await _supabase.from('post-images').delete().eq('post_id', postId);

      debugPrint('Post image records deleted.');

      // ======================================================
      // STEP 6
      // DELETE POST
      // ======================================================

      await _supabase.from('posts').delete().eq('id', postId);

      debugPrint('Post deleted.');

      // ======================================================
      // STEP 7
      // REMOVE FROM LOCAL LIST
      // ======================================================

      if (!mounted) {
        return;
      }

      setState(() {
        _posts.removeWhere(
          (post) => post['id'].toString() == postId.toString(),
        );

        if (_offset > 0) {
          _offset--;
        }

        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post, images, and comments deleted successfully.'),
        ),
      );
    } on PostgrestException catch (e) {
      debugPrint('======================================');

      debugPrint('DELETE POST SUPABASE ERROR');

      debugPrint('Message: ${e.message}');

      debugPrint('Code: ${e.code}');

      debugPrint('Details: ${e.details}');

      debugPrint('Hint: ${e.hint}');

      debugPrint('======================================');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete post: ${e.message}')),
      );
    } catch (e) {
      debugPrint('DELETE POST ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete post: $e')));
    }
  }

  // ==========================================================
  // EDIT POST
  // ==========================================================

  Future<void> _editPost(Map<String, dynamic> post) async {
    final bool? updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => EditPostPage(post: post)),
    );

    if (updated == true) {
      await _refreshPosts();
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final String? userEmail = currentUser?['email']?.toString();

    final bool isAdmin = userEmail == 'jeromeaw02@gmail.com';

    final String username =
        currentUser?['username']?.toString() ?? (isAdmin ? 'Boss' : 'Visitor');

    final String? profilePic = currentUser?['profile_pic']?.toString().trim();

    final bool hasProfilePic = profilePic != null && profilePic.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ==================================================
              // HEADER
              // ==================================================
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/jv_logo.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(Icons.person),
                        );
                      },
                    ),
                  ),

                  const SizedBox(width: 12),

                  const Text(
                    'Jerome Vlog',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const Spacer(),

                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfilePage(),
                        ),
                      );

                      await _refreshPosts();

                      if (mounted) {
                        setState(() {});
                      }
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.deepPurple.shade100,
                      backgroundImage: hasProfilePic
                          ? NetworkImage(profilePic!)
                          : null,
                      child: !hasProfilePic
                          ? const Icon(
                              Icons.person,
                              color: Colors.deepPurple,
                              size: 28,
                            )
                          : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ==================================================
              // WELCOME
              // ==================================================
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome back,',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        username,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ==================================================
              // CREATE POST
              // ==================================================
              if (isAdmin)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreatePostPage(),
                        ),
                      );

                      await _refreshPosts();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      alignment: Alignment.centerLeft,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "What's on your mind, Boss $username?",
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // ==================================================
              // POSTS
              // ==================================================
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshPosts,
                  child: _buildPostList(isAdmin),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // POST LIST
  // ==========================================================

  Widget _buildPostList(bool isAdmin) {
    if (_posts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty && !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 150),
          Center(child: Text('No posts yet')),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),

      itemCount: _posts.length + (_hasMore ? 1 : 0),

      itemBuilder: (context, index) {
        // ======================================================
        // PAGINATION LOADER
        // ======================================================

        if (index == _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final Map<String, dynamic> post = _posts[index];

        final dynamic postId = post['id'];

        final String title = post['title']?.toString() ?? 'Untitled';

        final String description =
            post['description']?.toString() ?? 'No description';

        final List<Map<String, dynamic>> images =
            (post['images'] as List?)
                ?.map((image) => Map<String, dynamic>.from(image))
                .toList() ??
            [];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          clipBehavior: Clip.antiAlias,

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ==================================================
              // IMAGE COLLAGE
              // ==================================================
              if (images.isNotEmpty) _buildImageCollage(images),

              // ==================================================
              // CONTENT
              // ==================================================
              Padding(
                padding: const EdgeInsets.all(12),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(description),

                    const SizedBox(height: 12),

                    // ==================================================
                    // BUTTONS
                    // ==================================================
                    Row(
                      children: [
                        if (isAdmin) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _editPost(post);
                              },
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit'),
                            ),
                          ),

                          const SizedBox(width: 6),

                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                _deletePost(postId);
                              },
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('Delete'),
                            ),
                          ),
                        ] else
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: images.isNotEmpty
                                  ? () {
                                      _openImageViewer(images, 0);
                                    }
                                  : null,
                              icon: const Icon(
                                Icons.comment_outlined,
                                size: 18,
                              ),
                              label: const Text('View Comments'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================================
// FULL-SCREEN IMAGE VIEWER
// ==========================================================

class ImageViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> images;

  final int initialIndex;

  const ImageViewerPage({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _pageController;

  late int _currentIndex;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;

    _pageController = PageController(initialPage: widget.initialIndex);
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _pageController.dispose();

    super.dispose();
  }

  // ==========================================================
  // ADD COMMENT
  // ==========================================================

  Future<void> _addComment(dynamic imageId) async {
    final TextEditingController controller = TextEditingController();

    final String? comment = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Comment'),

          content: TextField(
            controller: controller,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Write a comment...',
              border: OutlineInputBorder(),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),

            ElevatedButton(
              onPressed: () {
                final String value = controller.text.trim();

                if (value.isEmpty) {
                  return;
                }

                Navigator.pop(context, value);
              },
              child: const Text('Comment'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (comment == null || comment.trim().isEmpty) {
      return;
    }

    final dynamic userId = currentUser?['id'];

    if (userId == null) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must log in first.')));

      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('comments')
          .insert({
            'user_id': userId,
            'image_id': imageId,
            'comment': comment.trim(),
          })
          .select(
            'id, user_id, image_id, '
            'comment, created_at, '
            'users(username, profile_pic)',
          )
          .single();

      final currentImage = widget.images[_currentIndex];

      final List<Map<String, dynamic>> comments =
          (currentImage['comments'] as List?)
              ?.map((comment) => Map<String, dynamic>.from(comment))
              .toList() ??
          [];

      comments.add(Map<String, dynamic>.from(response));

      if (!mounted) {
        return;
      }

      setState(() {
        currentImage['comments'] = comments;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Comment added.')));
    } on PostgrestException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add comment: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add comment: $e')));
    }
  }

  // ==========================================================
  // EDIT COMMENT
  // ==========================================================

  Future<void> _editComment(dynamic commentId, String currentComment) async {
    final TextEditingController controller = TextEditingController(
      text: currentComment,
    );

    final String? newComment = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Comment'),

          content: TextField(
            controller: controller,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Edit your comment...',
              border: OutlineInputBorder(),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),

            ElevatedButton(
              onPressed: () {
                final String value = controller.text.trim();

                if (value.isEmpty) {
                  return;
                }

                Navigator.pop(context, value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newComment == null || newComment.trim().isEmpty) {
      return;
    }

    final String? userId = currentUser?['id']?.toString();

    if (userId == null) {
      return;
    }

    try {
      await Supabase.instance.client
          .from('comments')
          .update({'comment': newComment.trim()})
          .eq('id', commentId)
          .eq('user_id', userId);

      final currentImage = widget.images[_currentIndex];

      final List<Map<String, dynamic>> comments =
          (currentImage['comments'] as List?)
              ?.map((comment) => Map<String, dynamic>.from(comment))
              .toList() ??
          [];

      final int index = comments.indexWhere(
        (comment) => comment['id'].toString() == commentId.toString(),
      );

      if (index != -1) {
        comments[index]['comment'] = newComment.trim();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        currentImage['comments'] = comments;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Comment updated.')));
    } on PostgrestException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to edit comment: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to edit comment: $e')));
    }
  }

  // ==========================================================
  // DELETE COMMENT
  // ==========================================================

  Future<void> _deleteComment(dynamic commentId) async {
    final String? userId = currentUser?['id']?.toString();

    if (userId == null) {
      return;
    }

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Comment'),

          content: const Text(
            'Are you sure you want to '
            'delete this comment?',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await Supabase.instance.client
          .from('comments')
          .delete()
          .eq('id', commentId)
          .eq('user_id', userId);

      final currentImage = widget.images[_currentIndex];

      final List<Map<String, dynamic>> comments =
          (currentImage['comments'] as List?)
              ?.map((comment) => Map<String, dynamic>.from(comment))
              .toList() ??
          [];

      comments.removeWhere(
        (comment) => comment['id'].toString() == commentId.toString(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        currentImage['comments'] = comments;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment deleted successfully.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete comment: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete comment: $e')));
    }
  }

  // ==========================================================
  // COMMENT LIST
  // ==========================================================

  Widget _buildComments(Map<String, dynamic> image) {
    final List<Map<String, dynamic>> comments =
        (image['comments'] as List?)
            ?.map((comment) => Map<String, dynamic>.from(comment))
            .toList() ??
        [];

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 250),
      color: Colors.white,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==================================================
          // COMMENTS HEADER
          // ==================================================
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              'Comments (${comments.length})',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),

          // ==================================================
          // SCROLLABLE COMMENTS
          // ==================================================
          Expanded(
            child: comments.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No comments yet.\nBe the first to comment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment = comments[index];

                      final String commentText =
                          comment['comment']?.toString() ?? '';

                      final dynamic commentUserId = comment['user_id'];

                      // ==================================================
                      // USER DATA
                      // ==================================================

                      final Map<String, dynamic>? user = comment['users'] is Map
                          ? Map<String, dynamic>.from(comment['users'])
                          : null;

                      final String username =
                          user?['username']?.toString().trim().isNotEmpty ==
                              true
                          ? user!['username'].toString().trim()
                          : 'Unknown User';

                      // ==================================================
                      // PROFILE IMAGE
                      // ==================================================

                      final String? profilePic = user?['profile_pic']
                          ?.toString()
                          .trim();

                      final bool hasProfilePic =
                          profilePic != null && profilePic.isNotEmpty;

                      // ==================================================
                      // CURRENT USER
                      // ==================================================

                      final String? currentUserId = currentUser?['id']
                          ?.toString();

                      final bool isOwner =
                          currentUserId != null &&
                          currentUserId == commentUserId?.toString();

                      // ==================================================
                      // COMMENT ITEM
                      // ==================================================

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),

                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            // ==================================================
                            // AVATAR
                            // ==================================================
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.deepPurple.shade100,
                              backgroundImage: hasProfilePic
                                  ? NetworkImage(profilePic!)
                                  : null,
                              child: !hasProfilePic
                                  ? const Icon(
                                      Icons.person,
                                      size: 20,
                                      color: Colors.deepPurple,
                                    )
                                  : null,
                            ),

                            const SizedBox(width: 10),

                            // ==================================================
                            // COMMENT TEXT
                            // ==================================================
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    username,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(commentText),
                                ],
                              ),
                            ),

                            // ==================================================
                            // EDIT / DELETE
                            // ==================================================
                            if (isOwner)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _editComment(comment['id'], commentText);
                                    },
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  IconButton(
                                    tooltip: 'Delete',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _deleteComment(comment['id']);
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // BUILD IMAGE VIEWER
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> currentImage = widget.images[_currentIndex];

    final String imageUrl = currentImage['image'].toString();

    return Scaffold(
      backgroundColor: Colors.black,

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,

        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: Column(
        children: [
          // ====================================================
          // IMAGE
          // ====================================================
          Expanded(
            child: PageView.builder(
              controller: _pageController,

              itemCount: widget.images.length,

              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },

              itemBuilder: (context, index) {
                final String url = widget.images[index]['image'].toString();

                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,

                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,

                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }

                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },

                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white,
                            size: 60,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // ====================================================
          // COMMENTS
          // ====================================================
          _buildComments(currentImage),

          // ====================================================
          // ADD COMMENT
          // ====================================================
          Container(
            color: Colors.white,

            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),

            child: SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(
                onPressed: () {
                  _addComment(currentImage['id']);
                },

                icon: const Icon(Icons.comment),

                label: const Text('Add Comment'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
