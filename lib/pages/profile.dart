import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:blog/main.dart';
import 'package:blog/services/auth_service.dart';

// ==========================================================
// PROFILE PAGE
// ==========================================================

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // ==========================================================
  // VARIABLES
  // ==========================================================

  final ImagePicker _imagePicker = ImagePicker();

  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _usernameController;

  String? _username;
  String? _email;
  String? _profilePic;

  // Selected image before pressing Save
  Uint8List? _selectedImage;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _username = currentUser?['username']?.toString() ?? '-';

    _email = currentUser?['email']?.toString();

    _profilePic = currentUser?['profile_pic']?.toString();

    _usernameController = TextEditingController(text: _username);
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  // ==========================================================
  // PICK IMAGE
  // ==========================================================

  Future<void> _pickProfileImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) {
        return;
      }

      final Uint8List bytes = await image.readAsBytes();

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedImage = bytes;
      });
    } catch (e) {
      debugPrint('PICK IMAGE ERROR: $e');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to select image: $e')));
    }
  }

  // ==========================================================
  // UPLOAD PROFILE IMAGE
  // ==========================================================

  Future<String?> _uploadProfileImage(Uint8List imageBytes) async {
    final String? userId = currentUser?['id']?.toString();

    if (userId == null) {
      throw Exception('User is not authenticated.');
    }

    try {
      final String filePath =
          '$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final storage = Supabase.instance.client.storage;

      await storage
          .from('profiles')
          .uploadBinary(
            filePath,
            imageBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final String publicUrl = storage.from('profiles').getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      debugPrint('PROFILE IMAGE UPLOAD ERROR: $e');

      rethrow;
    }
  }

  // ==========================================================
  // SAVE PROFILE
  // ==========================================================

  Future<void> _saveProfile() async {
    final String? userId = currentUser?['id']?.toString();

    if (userId == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You are not logged in.')));

      return;
    }

    final String newUsername = _usernameController.text.trim();

    if (newUsername.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username cannot be empty.')),
      );

      return;
    }

    if (!mounted) return;

    setState(() {
      _isSaving = true;
    });

    try {
      String? newProfilePic = _profilePic;

      // ======================================================
      // UPLOAD NEW PROFILE IMAGE
      // ======================================================

      if (_selectedImage != null) {
        newProfilePic = await _uploadProfileImage(_selectedImage!);
      }

      // ======================================================
      // UPDATE DATABASE
      // ======================================================

      final Map<String, dynamic> updateData = {'username': newUsername};

      if (newProfilePic != null && newProfilePic.isNotEmpty) {
        updateData['profile_pic'] = newProfilePic;
      }

      await Supabase.instance.client
          .from('users')
          .update(updateData)
          .eq('id', userId);

      // ======================================================
      // GET THE ACTUAL UPDATED USER FROM SUPABASE
      // ======================================================

      final updatedUser = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      // ======================================================
      // UPDATE GLOBAL CURRENT USER
      // ======================================================

      await setCurrentUser(Map<String, dynamic>.from(updatedUser));

      debugPrint('UPDATED CURRENT USER: $currentUser');

      debugPrint('UPDATED USERNAME: ${currentUser?['username']}');

      debugPrint('UPDATED PROFILE PIC: ${currentUser?['profile_pic']}');

      if (!mounted) return;

      // ======================================================
      // UPDATE PROFILE PAGE
      // ======================================================

      setState(() {
        _username = currentUser?['username']?.toString();

        _email = currentUser?['email']?.toString();

        _profilePic = currentUser?['profile_pic']?.toString();

        _usernameController.text = _username ?? '';

        _selectedImage = null;

        _isEditing = false;

        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } on PostgrestException catch (e) {
      debugPrint('UPDATE PROFILE ERROR');
      debugPrint('Message: ${e.message}');
      debugPrint('Code: ${e.code}');
      debugPrint('Details: ${e.details}');
      debugPrint('Hint: ${e.hint}');

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: ${e.message}')),
      );
    } catch (e) {
      debugPrint('SAVE PROFILE ERROR: $e');

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
    }
  }

  // ==========================================================
  // CANCEL EDIT
  // ==========================================================

  void _cancelEdit() {
    setState(() {
      _isEditing = false;

      _selectedImage = null;

      _usernameController.text = _username ?? '';
    });
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================

  Future<void> _logout() async {
    // ==========================================================
    // CONFIRM LOGOUT
    // ==========================================================

    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            // CANCEL
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),

            // LOGOUT
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    // User cancelled logout.
    if (shouldLogout != true) {
      return;
    }

    // ==========================================================
    // LOGOUT
    // ==========================================================

    try {
      if (mounted) {
        setState(() {
          _isSaving = true;
        });
      }

      // ========================================================
      // CLEAR CUSTOM USER SESSION
      //
      // This removes:
      // 1. currentUser from memory
      // 2. current_user from SharedPreferences
      // ========================================================

      await logoutUser();

      debugPrint('CURRENT USER AFTER LOGOUT: $currentUser');

      if (!mounted) {
        return;
      }

      // ========================================================
      // GO TO HOME PAGE
      //
      // Remove all previous pages so the user cannot press
      // Back and return to the authenticated profile page.
      // ========================================================

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('LOGOUT ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  // ==========================================================
  // PROFILE IMAGE
  // ==========================================================

  Widget _buildProfileImage() {
    // Show newly selected image first
    if (_selectedImage != null) {
      return ClipOval(
        child: Image.memory(
          _selectedImage!,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
        ),
      );
    }

    // Show saved profile image
    if (_profilePic != null && _profilePic!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          _profilePic!,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _defaultProfileIcon();
          },
        ),
      );
    }

    return _defaultProfileIcon();
  }

  // ==========================================================
  // DEFAULT PROFILE ICON
  // ==========================================================

  Widget _defaultProfileIcon() {
    return CircleAvatar(
      radius: 55,
      backgroundColor: Colors.deepPurple.shade100,
      child: const Icon(Icons.person, size: 65, color: Colors.deepPurple),
    );
  }

  // ==========================================================
  // BACK BUTTON
  // ==========================================================

  void _goBack() {
    // Return true to the previous page.
    //
    // The previous page can use this value
    // to refresh itself.
    Navigator.pop(context, true);
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ======================================================
      // APP BAR
      // ======================================================
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isSaving ? null : _goBack,
        ),
        title: const Text('Profile'),
        centerTitle: true,
      ),

      // ======================================================
      // BODY
      // ======================================================
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ==================================================
              // PROFILE CONTENT
              // ==================================================
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // ==================================================
                      // PROFILE PICTURE
                      // ==================================================
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          _buildProfileImage(),

                          if (_isEditing)
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.deepPurple,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: _isSaving ? null : _pickProfileImage,
                                icon: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ==================================================
                      // USERNAME
                      // ==================================================
                      if (_isEditing)
                        TextField(
                          controller: _usernameController,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                      else
                        Text(
                          _username ?? '',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                      const SizedBox(height: 6),

                      // ==================================================
                      // EMAIL
                      // ==================================================
                      Text(
                        _email ?? 'No email',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),

              // ==================================================
              // BOTTOM BUTTON AREA
              // ==================================================
              if (!_isEditing)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isEditing = true;
                        _selectedImage = null;
                        _usernameController.text = _username ?? '';
                      });
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Profile'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : _cancelEdit,
                        child: const Text('Cancel'),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),

              // ==================================================
              // SPACE BETWEEN EDIT AND LOGOUT
              // ==================================================
              const SizedBox(height: 12),

              // ==================================================
              // LOGOUT
              // ==================================================
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _logout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ),

              // Small responsive bottom padding
              SizedBox(height: MediaQuery.of(context).size.height * 0.02),
            ],
          ),
        ),
      ),
    );
  }
}
