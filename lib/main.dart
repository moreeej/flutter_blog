import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:blog/services/auth_service.dart';
import 'package:blog/pages/login.dart';
import 'package:blog/pages/landing.dart';

// ==========================================================
// MAIN
// ==========================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========================================================
  // LOAD ENVIRONMENT VARIABLES
  // ========================================================

  await dotenv.load(fileName: '.env');

  // ========================================================
  // INITIALIZE SUPABASE
  // ========================================================

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // ========================================================
  // RESTORE LOGGED-IN USER
  // ========================================================

  await loadCurrentUser();

  // ========================================================
  // START APPLICATION
  // ========================================================

  runApp(const MyApp());
}

// ==========================================================
// APP
// ==========================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jerome Vlog',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),

      home: currentUser != null ? const LandingPage() : const HomePage(),
    );
  }
}

// ==========================================================
// HOME PAGE
// ==========================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ========================================================
  // SUPABASE
  // ========================================================

  final SupabaseClient _supabase = Supabase.instance.client;

  // ========================================================
  // PAGINATION
  // ========================================================

  static const int _pageSize = 5;

  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _posts = [];

  bool _isLoading = false;
  bool _hasMore = true;

  int _offset = 0;

  // ========================================================
  // INIT
  // ========================================================

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    _loadPosts();
  }

  // ========================================================
  // DISPOSE
  // ========================================================

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    super.dispose();
  }

  // ========================================================
  // SCROLL
  // ========================================================

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

    // Load next page when 200px from bottom.
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadPosts();
    }
  }

  // ========================================================
  // LOAD POSTS
  // ========================================================

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
      // ====================================================
      // PAGINATION RANGE
      // ====================================================

      final int start = _offset;
      final int end = _offset + _pageSize - 1;

      debugPrint('Loading posts: $start - $end');

      // ====================================================
      // GET POSTS
      // ====================================================

      final List<dynamic> postsResponse = await _supabase
          .from('posts')
          .select('id, user_id, title, description')
          .order('id', ascending: false)
          .range(start, end);

      final List<Map<String, dynamic>> newPosts = postsResponse
          .map((post) => Map<String, dynamic>.from(post))
          .toList();

      // ====================================================
      // NO MORE POSTS
      // ====================================================

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

      // ====================================================
      // GET POST IDS
      // ====================================================

      final List<dynamic> postIds = newPosts
          .map((post) => post['id'])
          .where((id) => id != null)
          .toList();

      // ====================================================
      // GET IMAGES
      // ====================================================

      List<Map<String, dynamic>> imageRows = [];

      if (postIds.isNotEmpty) {
        final List<dynamic> imagesResponse = await _supabase
            .from('post-images')
            .select('id, post_id, image')
            .inFilter('post_id', postIds)
            .order('id', ascending: true);

        imageRows = imagesResponse
            .map((image) => Map<String, dynamic>.from(image))
            .toList();
      }

      // ====================================================
      // GET IMAGE IDS
      // ====================================================

      final List<dynamic> imageIds = imageRows
          .map((image) => image['id'])
          .where((id) => id != null)
          .toList();

      // ====================================================
      // GET COMMENTS
      //
      // We intentionally DO NOT use:
      //
      // users(username)
      //
      // Instead, users are fetched separately using
      // comments.user_id.
      // ====================================================

      List<Map<String, dynamic>> commentRows = [];

      if (imageIds.isNotEmpty) {
        final List<dynamic> commentsResponse = await _supabase
            .from('comments')
            .select('id, user_id, image_id, comment, created_at')
            .inFilter('image_id', imageIds)
            .order('created_at', ascending: true);

        commentRows = commentsResponse
            .map((comment) => Map<String, dynamic>.from(comment))
            .toList();
      }

      // ====================================================
      // GET COMMENT USER IDS
      // ====================================================

      final List<dynamic> userIds = commentRows
          .map((comment) => comment['user_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      // ====================================================
      // GET USERS
      //
      // users.id
      // users.username
      // users.profile_pic
      // ====================================================

      Map<String, Map<String, dynamic>> usersById = {};

      if (userIds.isNotEmpty) {
        final List<dynamic> usersResponse = await _supabase
            .from('users')
            .select('id, username, profile_pic')
            .inFilter('id', userIds);

        final List<Map<String, dynamic>> users = usersResponse
            .map((user) => Map<String, dynamic>.from(user))
            .toList();

        for (final user in users) {
          final dynamic userId = user['id'];

          if (userId == null) {
            continue;
          }

          usersById[userId.toString()] = user;
        }
      }

      // ====================================================
      // ATTACH USER TO COMMENT
      //
      // Each comment will now contain:
      //
      // comment['user']
      //   ├── id
      //   ├── username
      //   └── profile_pic
      // ====================================================

      for (final comment in commentRows) {
        final dynamic userId = comment['user_id'];

        if (userId == null) {
          comment['user'] = null;
          continue;
        }

        comment['user'] = usersById[userId.toString()];
      }

      // ====================================================
      // GROUP COMMENTS BY IMAGE
      // ====================================================

      final Map<String, List<Map<String, dynamic>>> commentsByImage = {};

      for (final comment in commentRows) {
        final dynamic imageId = comment['image_id'];

        if (imageId == null) {
          continue;
        }

        final String imageKey = imageId.toString();

        commentsByImage.putIfAbsent(imageKey, () => []);

        commentsByImage[imageKey]!.add(comment);
      }

      // ====================================================
      // GROUP IMAGES BY POST
      // ====================================================

      final Map<String, List<Map<String, dynamic>>> imagesByPost = {};

      for (final imageRow in imageRows) {
        final dynamic imageId = imageRow['id'];

        final dynamic postId = imageRow['post_id'];

        final String imageUrl = imageRow['image']?.toString() ?? '';

        if (imageId == null || postId == null || imageUrl.isEmpty) {
          continue;
        }

        final String imageKey = imageId.toString();

        final String postKey = postId.toString();

        // ==================================================
        // COMMENTS FOR THIS IMAGE
        // ==================================================

        final List<Map<String, dynamic>> comments =
            commentsByImage[imageKey] ?? [];

        // ==================================================
        // IMAGE OBJECT
        // ==================================================

        final Map<String, dynamic> imageData = {
          'id': imageId,
          'post_id': postId,
          'image': imageUrl,

          // Comments belong ONLY to this image.
          'comments': comments,
        };

        imagesByPost.putIfAbsent(postKey, () => []);

        imagesByPost[postKey]!.add(imageData);
      }

      // ====================================================
      // ATTACH IMAGES TO POSTS
      // ====================================================

      for (final post in newPosts) {
        final String postKey = post['id'].toString();

        post['images'] = imagesByPost[postKey] ?? <Map<String, dynamic>>[];
      }

      // ====================================================
      // UPDATE STATE
      // ====================================================

      if (!mounted) {
        return;
      }

      setState(() {
        _posts.addAll(newPosts);

        _offset += newPosts.length;

        _hasMore = newPosts.length == _pageSize;

        _isLoading = false;
      });

      // ====================================================
      // DEBUG
      // ====================================================

      debugPrint('Loaded posts: ${newPosts.length}');

      debugPrint('Total posts: ${_posts.length}');

      debugPrint('Next offset: $_offset');

      debugPrint('Has more: $_hasMore');

      // ====================================================
      // PRINT NESTED DATA
      // ====================================================

      for (final post in newPosts) {
        debugPrint('POST ${post['id']}: ${post['title']}');

        final List images = post['images'] as List? ?? [];

        for (final image in images) {
          debugPrint('  IMAGE ${image['id']}: ${image['image']}');

          final List comments = image['comments'] as List? ?? [];

          for (final comment in comments) {
            final Map<String, dynamic>? user = comment['user'] is Map
                ? Map<String, dynamic>.from(comment['user'])
                : null;

            debugPrint('    COMMENT: ${comment['comment']}');

            debugPrint('    USER ID: ${comment['user_id']}');

            debugPrint('    USERNAME: ${user?['username'] ?? 'Unknown'}');

            debugPrint('    PROFILE PIC: ${user?['profile_pic'] ?? 'None'}');
          }
        }
      }
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

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

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

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load posts: $e')));
    }
  }

  // ========================================================
  // OPEN IMAGE VIEWER
  // ========================================================

  void _openImageViewer(List<Map<String, dynamic>> images, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ImageGalleryPage(images: images, initialIndex: initialIndex),
      ),
    );
  }

  // ========================================================
  // IMAGE COLLAGE
  // ========================================================

  Widget _buildImageCollage(List<Map<String, dynamic>> images) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    // ======================================================
    // ONE IMAGE
    // ======================================================

    if (images.length == 1) {
      return GestureDetector(
        onTap: () {
          _openImageViewer(images, 0);
        },
        child: _buildCollageImage(images[0]['image'].toString(), height: 260),
      );
    }

    // ======================================================
    // TWO IMAGES
    // ======================================================

    if (images.length == 2) {
      return SizedBox(
        height: 260,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  _openImageViewer(images, 0);
                },
                child: _buildCollageImage(
                  images[0]['image'].toString(),
                  height: 260,
                ),
              ),
            ),

            const SizedBox(width: 2),

            Expanded(
              child: GestureDetector(
                onTap: () {
                  _openImageViewer(images, 1);
                },
                child: _buildCollageImage(
                  images[1]['image'].toString(),
                  height: 260,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ======================================================
    // THREE IMAGES
    // ======================================================

    if (images.length == 3) {
      return SizedBox(
        height: 260,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () {
                  _openImageViewer(images, 0);
                },
                child: _buildCollageImage(
                  images[0]['image'].toString(),
                  height: 260,
                ),
              ),
            ),

            const SizedBox(width: 2),

            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _openImageViewer(images, 1);
                      },
                      child: _buildCollageImage(
                        images[1]['image'].toString(),
                        height: double.infinity,
                      ),
                    ),
                  ),

                  const SizedBox(height: 2),

                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _openImageViewer(images, 2);
                      },
                      child: _buildCollageImage(
                        images[2]['image'].toString(),
                        height: double.infinity,
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

    // ======================================================
    // FOUR OR MORE IMAGES
    // ======================================================

    return SizedBox(
      height: 260,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _openImageViewer(images, 0);
                    },
                    child: _buildCollageImage(
                      images[0]['image'].toString(),
                      height: double.infinity,
                    ),
                  ),
                ),

                const SizedBox(height: 2),

                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _openImageViewer(images, 2);
                    },
                    child: _buildCollageImage(
                      images[2]['image'].toString(),
                      height: double.infinity,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 2),

          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _openImageViewer(images, 1);
                    },
                    child: _buildCollageImage(
                      images[1]['image'].toString(),
                      height: double.infinity,
                    ),
                  ),
                ),

                const SizedBox(height: 2),

                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _openImageViewer(images, 3);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCollageImage(
                          images[3]['image'].toString(),
                          height: double.infinity,
                        ),

                        if (images.length > 4)
                          Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            child: Text(
                              '+${images.length - 4}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
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

  // ========================================================
  // COLLAGE IMAGE
  // ========================================================

  Widget _buildCollageImage(String imageUrl, {required double height}) {
    return Container(
      height: height,
      width: double.infinity,
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
    );
  }

  // ========================================================
  // SHOW LOGIN SNACKBAR
  // ========================================================

  void _showLoginRequiredMessage() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You must log in first to comment.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ========================================================
  // BUILD
  // ========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),

          child: Column(
            children: [
              // ==================================================
              // HEADER
              // ==================================================
              Row(
                children: [
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

                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2F2F2F),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // ==================================================
                  // LOGIN BUTTON
                  // ==================================================
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const Login()),
                      );
                    },

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C8FE2),

                      foregroundColor: Colors.white,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),

                    child: const Text('Login'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ==================================================
              // POSTS
              // ==================================================
              Expanded(child: _buildPostList()),
            ],
          ),
        ),
      ),
    );
  }

  // ========================================================
  // POST LIST
  // ========================================================

  Widget _buildPostList() {
    // ======================================================
    // INITIAL LOADING
    // ======================================================

    if (_posts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // ======================================================
    // NO POSTS
    // ======================================================

    if (_posts.isEmpty && !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),

        children: const [
          SizedBox(height: 150),

          Center(child: Text('No posts yet')),
        ],
      );
    }

    // ======================================================
    // POSTS
    // ======================================================

    return ListView.builder(
      controller: _scrollController,

      physics: const AlwaysScrollableScrollPhysics(),

      itemCount: _posts.length + (_hasMore ? 1 : 0),

      itemBuilder: (context, index) {
        // ==================================================
        // BOTTOM LOADING
        // ==================================================

        if (index == _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),

            child: Center(child: CircularProgressIndicator()),
          );
        }

        // ==================================================
        // POST
        // ==================================================

        final Map<String, dynamic> post = _posts[index];

        final String title = post['title']?.toString() ?? 'Untitled';

        final String description =
            post['description']?.toString() ?? 'No description';

        // ==================================================
        // IMAGES
        // ==================================================

        final List<Map<String, dynamic>> images =
            (post['images'] as List?)
                ?.map((image) => Map<String, dynamic>.from(image))
                .toList() ??
            [];

        // ==================================================
        // TOTAL COMMENTS
        // ==================================================

        int totalComments = 0;

        for (final image in images) {
          final List comments = image['comments'] as List? ?? [];

          totalComments += comments.length;
        }

        // ==================================================
        // POST CARD
        // ==================================================

        return Card(
          margin: const EdgeInsets.only(bottom: 16),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),

          clipBehavior: Clip.antiAlias,

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ==================================================
              // IMAGE COLLAGE
              // ==================================================
              if (images.isNotEmpty) _buildImageCollage(images),

              // ==================================================
              // POST CONTENT
              // ==================================================
              Padding(
                padding: const EdgeInsets.all(16),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    // ==================================================
                    // TITLE
                    // ==================================================
                    Text(
                      title,

                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ==================================================
                    // DESCRIPTION
                    // ==================================================
                    Text(description),

                    const SizedBox(height: 12),

                    // ==================================================
                    // COMMENT COUNT + BUTTON
                    // ==================================================
                    Row(
                      children: [
                        const Icon(
                          Icons.comment_outlined,
                          size: 20,
                          color: Colors.grey,
                        ),

                        const SizedBox(width: 6),

                        Text(
                          '$totalComments comments',

                          style: const TextStyle(color: Colors.grey),
                        ),

                        const Spacer(),

                        TextButton.icon(
                          onPressed: _showLoginRequiredMessage,

                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 18,
                          ),

                          label: const Text('Comment'),
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
// IMAGE GALLERY PAGE
//
// Each image is displayed individually.
// Each image has its OWN comments.
// ==========================================================

class ImageGalleryPage extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;

  const ImageGalleryPage({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  // ========================================================
  // PAGE CONTROLLER
  // ========================================================

  late final PageController _pageController;

  int _currentIndex = 0;

  // ========================================================
  // INIT
  // ========================================================

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;

    _pageController = PageController(initialPage: widget.initialIndex);
  }

  // ========================================================
  // DISPOSE
  // ========================================================

  @override
  void dispose() {
    _pageController.dispose();

    super.dispose();
  }

  // ========================================================
  // GET CURRENT IMAGE
  // ========================================================

  Map<String, dynamic> get _currentImage {
    return widget.images[_currentIndex];
  }

  // ========================================================
  // GET CURRENT COMMENTS
  // ========================================================

  List<Map<String, dynamic>> get _currentComments {
    final List comments = _currentImage['comments'] as List? ?? [];

    return comments
        .map((comment) => Map<String, dynamic>.from(comment))
        .toList();
  }

  // ========================================================
  // BUILD
  // ========================================================

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> comments = _currentComments;

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,

        title: Text('${_currentIndex + 1} / ${widget.images.length}'),

        actions: [
          IconButton(
            onPressed: () {
              Navigator.pop(context);
            },

            icon: const Icon(Icons.close),
          ),
        ],
      ),

      body: Column(
        children: [
          // ==================================================
          // IMAGE
          // ==================================================
          Expanded(
            flex: 6,

            child: PageView.builder(
              controller: _pageController,

              itemCount: widget.images.length,

              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },

              itemBuilder: (context, index) {
                final String imageUrl = widget.images[index]['image']
                    .toString();

                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,

                  child: Center(
                    child: Image.network(
                      imageUrl,

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

          // ==================================================
          // IMAGE INDICATORS
          // ==================================================
          if (widget.images.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),

              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: List.generate(widget.images.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),

                    margin: const EdgeInsets.symmetric(horizontal: 3),

                    width: index == _currentIndex ? 22 : 7,

                    height: 7,

                    decoration: BoxDecoration(
                      color: index == _currentIndex
                          ? Colors.white
                          : Colors.grey.shade600,

                      borderRadius: BorderRadius.circular(10),
                    ),
                  );
                }),
              ),
            ),

          // ==================================================
          // COMMENTS SECTION
          // ==================================================
          Expanded(
            flex: 4,

            child: Container(
              width: double.infinity,

              decoration: const BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  // ==============================================
                  // HEADER
                  // ==============================================
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),

                    child: Row(
                      children: [
                        const Icon(
                          Icons.comment_outlined,
                          color: Colors.black87,
                        ),

                        const SizedBox(width: 8),

                        Text(
                          'Comments (${comments.length})',

                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // ==============================================
                  // COMMENTS
                  // ==============================================
                  Expanded(
                    child: comments.isEmpty
                        ? const Center(
                            child: Text(
                              'No comments on this image',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),

                            itemCount: comments.length,

                            itemBuilder: (context, index) {
                              return _buildComment(comments[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================
  // BUILD COMMENT
  // ========================================================

  Widget _buildComment(Map<String, dynamic> comment) {
    // ======================================================
    // COMMENT TEXT
    // ======================================================

    final String commentText = comment['comment']?.toString() ?? '';

    // ======================================================
    // USER
    // ======================================================

    final Map<String, dynamic>? user = comment['user'] is Map
        ? Map<String, dynamic>.from(comment['user'])
        : null;

    // ======================================================
    // USERNAME
    // ======================================================

    final String? usernameValue = user?['username']?.toString().trim();

    final String username = usernameValue != null && usernameValue.isNotEmpty
        ? usernameValue
        : 'Unknown User';

    // ======================================================
    // PROFILE PICTURE
    // ======================================================

    final String profilePic = user?['profile_pic']?.toString().trim() ?? '';

    // ======================================================
    // COMMENT CARD
    // ======================================================

    return Container(
      width: double.infinity,

      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.all(12),

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
          _buildProfileAvatar(profilePic, username),

          const SizedBox(width: 10),

          // ==================================================
          // COMMENT CONTENT
          // ==================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  username,

                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 4),

                Text(commentText),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================
  // PROFILE AVATAR
  // ========================================================

  Widget _buildProfileAvatar(String profilePic, String username) {
    // ======================================================
    // NO PROFILE PICTURE
    // ======================================================

    if (profilePic.isEmpty) {
      return CircleAvatar(
        radius: 18,

        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',

          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }

    // ======================================================
    // PROFILE PICTURE
    // ======================================================

    return CircleAvatar(
      radius: 18,

      backgroundColor: Colors.grey.shade300,

      backgroundImage: NetworkImage(profilePic),

      onBackgroundImageError: (exception, stackTrace) {
        debugPrint('PROFILE IMAGE ERROR: $exception');
      },
    );
  }
}
