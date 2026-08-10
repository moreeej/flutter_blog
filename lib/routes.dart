import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'main.dart';
import 'pages/login.dart';
import 'pages/signup.dart';

import 'pages/landing.dart';
import 'pages/createPost.dart';
import 'pages/profile.dart';
import 'pages/editPost.dart';


final GoRouter appRouter = GoRouter(
  initialLocation: '/homepage',

  routes: [
    GoRoute(
      path: '/homepage',
      name: 'homepage',
      builder: (context, state) => const HomePage(),
    ),

    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const Login(),
    ),

    GoRoute(
      path: '/signup',
      name: 'signup',
      builder: (context, state) => const Signup(),
    ),



    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const LandingPage(),
    ),

    GoRoute(
      path: '/create-post',
      name: 'create-post',
      builder: (context, state) => const CreatePostPage(),
    ),

    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfilePage(),
    ),
     GoRoute(
      path: '/edit-post',
      name: 'edit-post',
      builder: (context, state) => const EditPostPage(post: {},),
    ),
  ],
);