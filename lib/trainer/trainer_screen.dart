import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../teams/team_membership.dart';
import 'trainer_profile.dart';

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key, this.repository});
  final TrainerRepository? repository;
  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen>
    with WidgetsBindingObserver {
  late final TrainerRepository repo;
  StreamSubscription<void>? subscription;
  TrainerSnapshot? data;
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  final username = TextEditingController(),
      name = TextEditingController(),
      bio = TextEditingController();
  bool editing = false, busy = false, loading = false, again = false;
  String? error, notice, avatar;
  Uint8List? preview;
  int editRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo =
        widget.repository ??
        SupabaseTrainerRepository(Supabase.instance.client);
    unawaited(_start());
  }

  Future<void> _start() async {
    await refresh();
    if (!mounted) return;
    subscription = repo.watch().listen(
      (_) {
        unawaited(refresh());
      },
      onError: (Object _) {
        if (mounted) {
          setState(
            () => error = 'Live updates disconnected. Refresh to reconnect.',
          );
        }
      },
    );
    if (widget.repository == null &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _recoverPhoto();
      } catch (_) {
        if (mounted) {
          setState(
            () => error =
                'Your interrupted photo could not be recovered. Choose it again to retry.',
          );
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (loading) {
      again = true;
      return;
    }
    loading = true;
    try {
      final next = await repo.load();
      if (!mounted) return;
      setState(() {
        data = next;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to load your trainer. Check your connection and retry.',
        );
      }
    } finally {
      loading = false;
      if (again && mounted) {
        again = false;
        unawaited(refresh());
      }
    }
  }

  void edit() {
    final p = data!.profile;
    editRevision = p['revision'] as int;
    setState(() {
      editing = true;
      username.text = p['username'] as String? ?? '';
      name.text = p['display_name'] as String;
      bio.text = p['bio'] as String;
      avatar = p['avatar_path'] as String?;
      preview = null;
      notice = null;
    });
  }

  Future<void> _recoverPhoto() async {
    final preferences = await SharedPreferences.getInstance();
    final owner = preferences.getString('trainer_pending_photo_user');
    if (owner == null) return;
    final response = await ImagePicker().retrieveLostData();
    await preferences.remove('trainer_pending_photo_user');
    if (!mounted || owner != Supabase.instance.client.auth.currentUser?.id) {
      return;
    }
    if (response.files?.isNotEmpty == true && data != null) {
      edit();
      await _photo(response.files!.first);
      if (mounted) {
        setState(
          () => notice = 'Recovered your photo. Review your profile and save.',
        );
      }
    }
  }

  Future<void> pickPhoto() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'trainer_pending_photo_user',
      Supabase.instance.client.auth.currentUser!.id,
    );
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      await preferences.remove('trainer_pending_photo_user');
      if (photo != null && mounted) await _photo(photo);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to open that photo. Try another JPEG, PNG or WebP image.',
        );
      }
    }
  }

  Future<void> _photo(XFile file) async {
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final jpeg = await compute(prepareTrainerPhoto, await file.readAsBytes());
      final path = await repo.upload(jpeg);
      if (mounted) {
        setState(() {
          avatar = path;
          preview = jpeg;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Photo upload failed. Choose another image or retry; your saved photo is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final revision = editRevision;
    setState(() => busy = true);
    try {
      await repo.save(
        username: username.text.trim().toLowerCase(),
        name: name.text.trim(),
        bio: bio.text.trim(),
        avatar: avatar,
        revision: revision,
      );
      if (!mounted) return;
      setState(() {
        editing = false;
        notice = 'Profile saved.';
        preview = null;
      });
      await refresh();
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(
          () => error = e.code == 'PT409'
              ? (e.message.startsWith('Your profile changed')
                    ? 'Your profile changed on another session. Cancel editing and reopen the editor before saving.'
                    : e.message)
              : 'Profile could not be saved. Check your entries and retry.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Save could not be confirmed. Refresh and check your profile before retrying.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (scroll.hasClients) {
          unawaited(
            scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
          );
        }
      }
    }
  }

  Future<void> leaveEditor() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard profile changes?'),
        content: const Text('Your saved profile will stay as it is.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => editing = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(subscription?.cancel());
    username.dispose();
    name.dispose();
    bio.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final team = TeamScope.of(context).team!;
    final d = data;
    return PopScope(
      canPop: !busy && !editing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy && editing) unawaited(leaveEditor());
      },
      child: Scaffold(
        backgroundColor: const Color(0xfff5f1e3),
        appBar: AppBar(
          title: const Text('Your trainer'),
          actions: [
            IconButton(
              tooltip: 'Refresh trainer',
              onPressed: busy ? null : refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: d == null
            ? Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!),
                          TextButton(
                            onPressed: refresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
              )
            : RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (error != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            error!,
                            key: const ValueKey('trainer-error'),
                          ),
                        ),
                      ),
                    if (notice != null)
                      Text(notice!, key: const ValueKey('trainer-notice')),
                    Center(
                      child: CircleAvatar(
                        radius: 52,
                        backgroundColor: team.color.withValues(alpha: .25),
                        child: ClipOval(
                          child: preview != null
                              ? Image.memory(
                                  preview!,
                                  width: 104,
                                  height: 104,
                                  fit: BoxFit.cover,
                                )
                              : (!editing || avatar != null) &&
                                    d.avatarUrl != null
                              ? Image.network(
                                  d.avatarUrl!,
                                  width: 104,
                                  height: 104,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.person_outline,
                                    size: 60,
                                  ),
                                )
                              : const Icon(Icons.person_outline, size: 60),
                        ),
                      ),
                    ),
                    if (d.photoUnavailable)
                      const Text(
                        'Photo unavailable. Refresh to retry.',
                        textAlign: TextAlign.center,
                      ),
                    if (editing) ...[
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: busy ? null : pickPhoto,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Choose photo'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() {
                                      avatar = null;
                                      preview = null;
                                    });
                                  },
                            child: const Text('Remove photo'),
                          ),
                        ],
                      ),
                      Form(
                        key: form,
                        child: Column(
                          children: [
                            TextFormField(
                              key: const ValueKey('trainer-username'),
                              controller: username,
                              maxLength: 20,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                helperText:
                                    'Unique · letters, numbers and underscores',
                              ),
                              validator: (v) =>
                                  RegExp(
                                    r'^[a-z][a-z0-9_]{2,19}$',
                                  ).hasMatch((v ?? '').trim().toLowerCase())
                                  ? null
                                  : 'Use 3–20 characters, starting with a letter.',
                            ),
                            TextFormField(
                              key: const ValueKey('trainer-name'),
                              controller: name,
                              maxLength: 32,
                              decoration: const InputDecoration(
                                labelText: 'Trainer name',
                              ),
                            ),
                            TextFormField(
                              key: const ValueKey('trainer-bio'),
                              controller: bio,
                              maxLength: 200,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'Bio',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: busy ? null : save,
                              child: const Text('Save profile'),
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() {
                                      editing = false;
                                      preview = null;
                                      error = null;
                                    });
                                  },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        d.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (d.profile['username'] != null)
                        Text(
                          '@${d.profile['username']}',
                          textAlign: TextAlign.center,
                        ),
                      if ((d.profile['bio'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            d.profile['bio'] as String,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: edit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit profile'),
                        ),
                      ),
                    ],
                    if (busy) const LinearProgressIndicator(),
                    Center(
                      child: Chip(
                        label: Text('${team.displayName} · Permanent team'),
                        avatar: Icon(Icons.flag, color: team.color),
                      ),
                    ),
                    if (widget.repository == null)
                      ExpansionTile(
                        title: const Text('Account details'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                SelectableText(
                                  Supabase
                                          .instance
                                          .client
                                          .auth
                                          .currentUser
                                          ?.email ??
                                      '',
                                ),
                                const SizedBox(height: 8),
                                Text(team.description),
                              ],
                            ),
                          ),
                        ],
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Level ${d.level} · ${d.rank}',
                              key: const ValueKey('trainer-level'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${d.xp} XP',
                              key: const ValueKey('trainer-xp'),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: d.fraction,
                              minHeight: 10,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              d.nextLevel == null
                                  ? 'Highest current level reached'
                                  : '${(d.nextLevel!['min_xp'] as num) - d.xp} XP to level ${d.nextLevel!['level']}',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${d.settings['correct_xp']} XP per correct kick · ${d.settings['perfect_xp']} perfect-attack bonus · ${d.settings['capture_xp']} capture bonus',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        for (final entry in {
                          'correct_kicks': 'Correct kicks',
                          'completed_attacks': 'Attacks finished',
                          'perfect_attacks': 'Perfect attacks',
                          'captures': 'Team captures',
                        }.entries)
                          Chip(
                            label: Text(
                              '${d.progress[entry.key]} ${entry.value}',
                            ),
                          ),
                      ],
                    ),
                    for (final kind in ['badge', 'achievement']) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 8),
                        child: Text(
                          kind == 'badge' ? 'Badges' : 'Achievements',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      for (final a in d.achievements.where(
                        (a) => a['kind'] == kind,
                      ))
                        Card(
                          child: ListTile(
                            leading: Text(
                              a['earned_at'] != null
                                  ? a['emblem'] as String
                                  : '🔒',
                              style: const TextStyle(fontSize: 28),
                            ),
                            title: Text(a['title'] as String),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a['description'] as String),
                                Text(
                                  a['earned_at'] != null
                                      ? 'Earned'
                                      : '${a['value']} / ${a['target']}',
                                ),
                                if (a['earned_at'] == null)
                                  LinearProgressIndicator(
                                    value:
                                        ((a['value'] as num) /
                                                (a['target'] as num))
                                            .clamp(0, 1)
                                            .toDouble(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (!d.achievements.any((a) => a['kind'] == kind))
                        const Text('More milestones are on their way.'),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
