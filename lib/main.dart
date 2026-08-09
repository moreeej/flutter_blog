import 'package:blog/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

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
      title: 'Flutter Form',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
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
  // ==========================================================
  // PAGINATION
  // ==========================================================

  static const int _pageSize = 5;

  final ScrollController _scrollController = ScrollController();

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
  // SCROLL
  // ==========================================================

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    // Prevent duplicate requests.
    if (_isLoading) {
      return;
    }

    // No more posts available.
    if (!_hasMore) {
      return;
    }

    final position = _scrollController.position;

    // Load the next 5 posts when the user
    // gets close to the bottom.
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadPosts();
    }
  }

  // ==========================================================
  // LOAD POSTS FROM SUPABASE
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
      // ========================================================
      // PAGINATION RANGE
      // ========================================================
      //
      // First request:
      // 0 - 4   = first 5 posts
      //
      // Second:
      // 5 - 9   = next 5 posts
      //
      // Third:
      // 10 - 14 = next 5 posts
      //
      // etc.

      final int start = _offset;
      final int end = _offset + _pageSize - 1;

      debugPrint('Loading posts: $start - $end');

      // ========================================================
      // SUPABASE QUERY
      // ========================================================

      final response = await Supabase.instance.client
          .from('posts')
          .select()
          .order('id', ascending: false)
          .range(start, end);

      // ========================================================
      // MAP SUPABASE RESPONSE
      // ========================================================

      final List<Map<String, dynamic>> newPosts = (response as List)
          .map((post) => Map<String, dynamic>.from(post))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        // Add the new 5 posts to
        // the existing list.
        _posts.addAll(newPosts);

        // Move offset forward.
        _offset += newPosts.length;

        // If Supabase returned fewer than
        // 5 posts, there are no more posts.
        _hasMore = newPosts.length == _pageSize;

        _isLoading = false;
      });

      debugPrint('Loaded: ${newPosts.length}');

      debugPrint('Total posts: ${_posts.length}');

      debugPrint('Next offset: $_offset');

      debugPrint('Has more: $_hasMore');
    } on PostgrestException catch (e) {
      debugPrint('SUPABASE ERROR');

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
  // BUILD
  // ==========================================================

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
                    borderRadius:
                        BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/jv_logo.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (
                            context,
                            error,
                            stackTrace,
                          ) {
                        return Container(
                          width: 48,
                          height: 48,
                          decoration:
                              BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius:
                                BorderRadius.circular(
                              24,
                            ),
                          ),
                          child: const Icon(
                            Icons.person,
                          ),
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
                  // LOGIN
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

  // ==========================================================
  // POST LIST
  // ==========================================================

  Widget _buildPostList() {
    // ==========================================================
    // INITIAL LOADING
    // ==========================================================

    if (_posts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // ==========================================================
    // NO POSTS
    // ==========================================================

    if (_posts.isEmpty && !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 150),
          Center(child: Text('No posts yet')),
        ],
      );
    }

    // ==========================================================
    // POST LIST
    // ==========================================================

    return ListView.builder(
      controller: _scrollController,

      physics: const AlwaysScrollableScrollPhysics(),

      // Add one extra item for
      // the bottom loading indicator.
      itemCount: _posts.length + (_hasMore ? 1 : 0),

      itemBuilder: (context, index) {
        // ========================================================
        // BOTTOM LOADING INDICATOR
        // ========================================================

        if (index == _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // ========================================================
        // GET POST
        // ========================================================

        final post = _posts[index];

        // ========================================================
        // MAP DATABASE COLUMNS
        // ========================================================

        final String title = post['title']?.toString() ?? 'Untitled';

        final String description =
            post['description']?.toString() ?? 'No description';

        final String? imageUrl = post['image']?.toString();

        // ========================================================
        // POST CARD
        // ========================================================

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
              // IMAGE
              // ==================================================
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Image.network(
                    imageUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,

                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      return const SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },

                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 180,
                        width: double.infinity,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image, size: 50),
                      );
                    },
                  ),
                ),

              // ==================================================
              // CONTENT
              // ==================================================
              Padding(
                padding: const EdgeInsets.all(16),
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
                    // ACTION BUTTONS
                    // ==================================================
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'You must log in first to comment.',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.comment_outlined),
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
