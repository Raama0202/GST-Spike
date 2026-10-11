import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/widgets.dart';

final announcementHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final dio = ref.watch(dioProvider);
      try {
        return itemList((await dio.get(ApiPaths.announcements)).data);
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status != 404 && status != 405) rethrow;
      }
      // Servers without the grouped endpoint: derive history from the feed.
      final response = await dio.get(
        ApiPaths.notifications,
        queryParameters: {'type': 'companyAnnouncement', 'pageSize': 500},
      );
      final seen = <String>{};
      return [
        for (final item in itemList(response.data))
          if (item['type'] == 'companyAnnouncement' &&
              seen.add('${item['title']}|${item['body']}'))
            item,
      ];
    });

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final confirmed = await confirmAction(
      context,
      title: 'Send announcement?',
      message: 'This message will be sent to all active employees.',
      confirmLabel: 'Send now',
    );
    if (!confirmed) return;
    setState(() => _sending = true);
    try {
      final response = await ref
          .read(dioProvider)
          .post(
            ApiPaths.announcements,
            data: {
              'title': _title.text.trim(),
              'body': _message.text.trim(),
            },
          );
      _title.clear();
      _message.clear();
      ref.invalidate(announcementHistoryProvider);
      if (mounted) {
        final created = (response.data as Map?)?['created'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Announcement sent to $created employees.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Announcements',
          subtitle: 'Send an operational update to every active employee.',
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a title'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _message,
                      maxLines: 8,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a message'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          _sending ? 'Sending…' : 'Send announcement',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Recent announcements',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Card(
          child: ref
              .watch(announcementHistoryProvider)
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => ErrorPanel(
                  message: apiError(error),
                  onRetry: () => ref.invalidate(announcementHistoryProvider),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyPanel(
                        icon: Icons.campaign_outlined,
                        title: 'No announcements yet',
                        message: 'Sent announcements will appear here.',
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => ListTile(
                          title: Text('${items[index]['title']}'),
                          subtitle: Text('${items[index]['body']}'),
                          trailing: items[index]['recipients'] == null
                              ? null
                              : Text(
                                  '${items[index]['read'] ?? 0}/${items[index]['recipients']} read',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                        ),
                      ),
              ),
        ),
      ],
    ),
  );
}
