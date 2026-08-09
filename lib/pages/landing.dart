import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blog/services/auth_service.dart';

import 'package:blog/pages/createPost.dart';
import 'package:blog/pages/profile.dart';

void main() {
  runApp(const LandingPage());
}

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

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  // ==========================================================
  // PAGINATION VARIABLES
  // ==========================================================

  final ScrollController _scrollController = ScrollController();

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

    // Load the first 5 posts.
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
  // SCROLL / PAGINATION
  // ==========================================================

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    // Do not request another page while loading.
    if (_isLoading) {
      return;
    }

    // Do not request another page if there are no more posts.
    if (!_hasMore) {
      return;
    }

    final position = _scrollController.position;

    // Load the next 5 posts when the user
    // is within 200 pixels of the bottom.
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadPosts();
    }
  }

  // ==========================================================
  // LOAD POSTS
  // ==========================================================

  Future<void> _loadPosts() async {
    // Prevent duplicate requests.
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
      // Example:
      //
      // First request:
      // range(0, 4)
      //
      // Second request:
      // range(5, 9)
      //
      // Third request:
      // range(10, 14)

      final int start = _offset;
      final int end = _offset + _pageSize - 1;

      debugPrint('Loading posts from $start to $end');

      final response = await Supabase.instance.client
          .from('posts')
          .select()
          .order('id', ascending: false)
          .range(start, end);

      final List<Map<String, dynamic>> newPosts = (response as List)
          .map((post) => Map<String, dynamic>.from(post))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        // Add new posts to existing posts.
        _posts.addAll(newPosts);

        // Move pagination forward.
        _offset += newPosts.length;

        // If less than 5 were returned,
        // there are no more posts.
        _hasMore = newPosts.length == _pageSize;

        _isLoading = false;
      });

      debugPrint('Loaded ${newPosts.length} posts');

      debugPrint('Total posts: ${_posts.length}');

      debugPrint('Next offset: $_offset');

      debugPrint('Has more: $_hasMore');
    } on PostgrestException catch (e) {
      debugPrint('SUPABASE POSTS ERROR');
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

      // Reset pagination.
      _offset = 0;
      _hasMore = true;
      _isLoading = false;
    });

    await _loadPosts();
  }

  // ==========================================================
  // DELETE POST
  // ==========================================================

  Future<void> _deletePost(dynamic postId) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Post'),
          content: const Text('Are you sure you want to delete this post?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
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
      await Supabase.instance.client.from('posts').delete().eq('id', postId);

      if (!mounted) {
        return;
      }

      setState(() {
        _posts.removeWhere((post) => post['id'] == postId);

        // Keep offset synchronized with the
        // number of posts currently displayed.
        if (_offset > 0) {
          _offset--;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted successfully.')),
      );
    } on PostgrestException catch (e) {
      debugPrint('DELETE POST ERROR');

      debugPrint('Message: ${e.message}');

      debugPrint('Code: ${e.code}');

      debugPrint('Details: ${e.details}');

      debugPrint('Hint: ${e.hint}');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete post: ${e.message}')),
      );
    } catch (e) {
      debugPrint('DELETE POST ERROR: $e');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete post: $e')));
    }
  }

  // ==========================================================
  // EDIT POST
  // ==========================================================

  void _editPost(Map<String, dynamic> post) {
    // Connect your EditPostPage here.

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit post page is not connected yet.')),
    );
  }

  // ==========================================================
  // COMMENT POST
  // ==========================================================

  void _commentPost(dynamic postId) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You must log in first')));
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final String? userEmail = currentUser?['email']?.toString();

    final bool isAdmin = userEmail == 'jeromeaw02@gmail.com';

    final String username =
        currentUser?['username']?.toString() ??
        (isAdmin ? 'Boss' : 'Visitor');

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

                  // PROFILE AVATAR
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfilePage(),
                        ),
                      );

                      // Refresh Landing Page when returning from Profile
                      await _refreshPosts();

                      setState(() {});
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.deepPurple.shade100,
                      backgroundImage:
                          currentUser?['profile_pic'] != null &&
                              currentUser!['profile_pic']
                                  .toString()
                                  .isNotEmpty
                          ? NetworkImage(
                              currentUser!['profile_pic'].toString(),
                            )
                          : null,
                      child:
                          currentUser?['profile_pic'] == null ||
                              currentUser!['profile_pic']
                                  .toString()
                                  .isEmpty
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
              // PROFILE / WELCOME SECTION
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

                      // Reload posts after
                      // returning from Create Post.
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
                      "What's on your mind, Boss "
                      "$username?",
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // ==================================================
              // POST LIST
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
    // Initial loading state.
    if (_posts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // No posts.
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

      // Add one extra item for the
      // bottom loading indicator.
      itemCount: _posts.length + (_hasMore ? 1 : 0),

      itemBuilder: (context, index) {
        // ======================================================
        // BOTTOM LOADING INDICATOR
        // ======================================================

        if (index == _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // ======================================================
        // POST DATA
        // ======================================================

        final Map<String, dynamic> post = _posts[index];

        final String title = post['title']?.toString() ?? 'Untitled';

        final String description =
            post['description']?.toString() ?? 'No description';

        final String? imageUrl = post['image']?.toString();

        final dynamic postId = post['id'];

        // ======================================================
        // POST CARD
        // ======================================================

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================================================
              // POST IMAGE
              // ==================================================
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: Image.network(
                    imageUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,

                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      return const SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },

                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 220,
                        width: double.infinity,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image, size: 50),
                      );
                    },
                  ),
                ),

              // ==================================================
              // POST CONTENT
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
                        // ==================================================
                        // ADMIN BUTTONS
                        // ==================================================
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
                              onPressed: () {
                                _deletePost(postId);
                              },
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('Delete'),
                            ),
                          ),
                        ]
                        // ==================================================
                        // COMMENT BUTTON - NON ADMIN ONLY
                        // ==================================================
                        else
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _commentPost(postId);
                              },
                              icon: const Icon(
                                Icons.comment_outlined,
                                size: 18,
                              ),
                              label: const Text('Comment'),
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
