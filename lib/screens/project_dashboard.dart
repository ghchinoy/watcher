import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';
import '../widgets/view_mode_segmented_control.dart';
import '../widgets/activity_ticker.dart';
import '../widgets/planner_modal.dart';
import '../widgets/assessment_modal.dart';

class ProjectDashboard extends StatelessWidget {
  const ProjectDashboard({super.key});

  void _showPlanner(BuildContext context) {
    showMacosSheet(
      context: context,
      builder: (context) =>
          MacosSheet(child: PlannerModal(project: appState.selectedProject!)),
    );
  }

  void _showAssessment(BuildContext context) {
    showMacosSheet(
      context: context,
      builder: (context) => MacosSheet(
        child: AssessmentModal(project: appState.selectedProject!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.selectedProject == null) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Dashboard'),
              actions: [
                ToolBarIconButton(
                  label: 'Toggle Inspector',
                  icon: const MacosIcon(CupertinoIcons.sidebar_right),
                  showLabel: false,
                  tooltipMessage: 'Toggle Inspector',
                  onPressed: () =>
                      MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
                ),
                CustomToolbarItem(
                  inToolbarBuilder: (context) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: ViewModeSegmentedControl(currentRoute: '/'),
                  ),
                ),
              ],
            ),
            children: [
              ContentArea(
                builder: (context, scrollController) => const Center(
                  child: Text('No project selected. Add one from the sidebar.'),
                ),
              ),
            ],
          );
        }

        if (appState.isLoading) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Dashboard'),
              actions: [
                ToolBarIconButton(
                  label: 'Toggle Inspector',
                  icon: const MacosIcon(CupertinoIcons.sidebar_right),
                  showLabel: false,
                  tooltipMessage: 'Toggle Inspector',
                  onPressed: () =>
                      MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
                ),
                CustomToolbarItem(
                  inToolbarBuilder: (context) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: ViewModeSegmentedControl(currentRoute: '/'),
                  ),
                ),
              ],
            ),
            children: [
              ContentArea(
                builder: (context, scrollController) =>
                    const Center(child: ProgressCircle()),
              ),
            ],
          );
        }

        if (appState.error != null) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Dashboard'),
              actions: [
                ToolBarIconButton(
                  label: 'Toggle Inspector',
                  icon: const MacosIcon(CupertinoIcons.sidebar_right),
                  showLabel: false,
                  tooltipMessage: 'Toggle Inspector',
                  onPressed: () =>
                      MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
                ),
                CustomToolbarItem(
                  inToolbarBuilder: (context) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: ViewModeSegmentedControl(currentRoute: '/'),
                  ),
                ),
              ],
            ),
            children: [
              ContentArea(
                builder: (context, scrollController) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Error: ${appState.error}',
                          style: const TextStyle(
                            color: MacosColors.systemRedColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        PushButton(
                          controlSize: ControlSize.regular,
                          onPressed: () {
                            if (appState.selectedProject != null) {
                              appState.selectProject(appState.selectedProject!);
                            }
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final issues = appState.currentIssues;
        final openCount = issues.where((i) => i.status == 'open').length;
        final openP1Count = issues
            .where((i) => i.status == 'open' && i.priority == 1)
            .length;
        final openP2Count = issues
            .where((i) => i.status == 'open' && i.priority == 2)
            .length;
        final openP3Count = issues
            .where((i) => i.status == 'open' && i.priority == 3)
            .length;
        final inProgressCount = issues
            .where((i) => i.status == 'in_progress')
            .length;
        final closedCount = issues.where((i) => i.status == 'closed').length;

        return MacosScaffold(
          toolBar: ToolBar(
            leading: MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.sidebar_left),
              onPressed: () {
                MacosWindowScope.of(context).toggleSidebar();
              },
            ),
            title: Text(appState.selectedProject!.name),
            actions: [
              ToolBarIconButton(
                label: 'AI Health Assessment',
                icon: const MacosIcon(CupertinoIcons.heart),
                showLabel: false,
                tooltipMessage: 'AI Health Assessment',
                onPressed: () => _showAssessment(context),
              ),
              ToolBarIconButton(
                label: 'AI Planner',
                icon: const MacosIcon(CupertinoIcons.sparkles),
                showLabel: false,
                tooltipMessage: 'AI Planner',
                onPressed: () => _showPlanner(context),
              ),
              ToolBarIconButton(
                label: 'Toggle Inspector',
                icon: const MacosIcon(CupertinoIcons.sidebar_right),
                showLabel: false,
                tooltipMessage: 'Toggle Inspector',
                onPressed: () =>
                    MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
              ),
              CustomToolbarItem(
                inToolbarBuilder: (context) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: ViewModeSegmentedControl(currentRoute: '/'),
                ),
              ),
            ],
          ),
          children: [
            ContentArea(
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project Overview',
                        style: MacosTheme.of(context).typography.largeTitle,
                      ),
                      const SizedBox(height: 20),
                      if (appState.projectRequiredVersion != null &&
                          appState.daemonVersion != null &&
                          appState.projectRequiredVersion != appState.daemonVersion)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MacosColors.systemRedColor.withValues(alpha: 0.1),
                              border: Border.all(color: MacosColors.systemRedColor),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const MacosIcon(CupertinoIcons.exclamationmark_octagon_fill, color: MacosColors.systemRedColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Incompatible Version: This project requires beads version ${appState.projectRequiredVersion}, but your Watcher daemon is running ${appState.daemonVersion}. Some features may be broken or unreadable.',
                                    style: MacosTheme.of(context).typography.body,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          SimpleStatCard(
                            title: 'Open',
                            value: openCount.toString(),
                          ),
                          const SizedBox(width: 16),
                          PriorityStatCard(
                            p0Count: issues
                                .where(
                                  (i) => i.status == 'open' && i.priority == 0,
                                )
                                .length,
                            p1Count: openP1Count,
                            p2Count: openP2Count,
                            p3Count: openP3Count,
                          ),
                          const SizedBox(width: 16),
                          SimpleStatCard(
                            title: 'In Progress',
                            value: inProgressCount.toString(),
                          ),
                          const SizedBox(width: 16),
                          SimpleStatCard(
                            title: 'Closed',
                            value: closedCount.toString(),
                          ),
                          const SizedBox(width: 16),
                          SimpleStatCard(
                            title: 'Total',
                            value: issues.length.toString(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Federation',
                        style: MacosTheme.of(context).typography.title2,
                      ),
                      const SizedBox(height: 12),
                      if (appState.currentPeers.isEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: MacosDynamicColor.resolve(
                              MacosColors.controlBackgroundColor,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: MacosColors.systemGrayColor.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No peers configured',
                                  style: MacosTheme.of(
                                    context,
                                  ).typography.headline,
                                ),
                                const SizedBox(height: 4),
                                const Text('This project only exists locally.'),
                                const SizedBox(height: 12),
                                PushButton(
                                  controlSize: ControlSize.regular,
                                  child: const Text('Configure Federation...'),
                                  onPressed: () {
                                    context.go('/project/settings');
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: MacosDynamicColor.resolve(
                              MacosColors.controlBackgroundColor,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: MacosColors.systemGrayColor.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${appState.currentPeers.length} Peers Configured',
                                      style: MacosTheme.of(
                                        context,
                                      ).typography.headline,
                                    ),
                                    PushButton(
                                      controlSize: ControlSize.regular,
                                      secondary: true,
                                      onPressed: () {
                                        appState.syncPeer();
                                      },
                                      child: const Text('Sync All'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ...appState.currentPeers.map(
                                  (peer) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      children: [
                                        const MacosIcon(
                                          CupertinoIcons.cloud,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          peer['name'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          peer['url'] ?? '',
                                          style: MacosTheme.of(context)
                                              .typography
                                              .footnote
                                              .copyWith(
                                                color:
                                                    MacosColors.systemGrayColor,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                PushButton(
                                  controlSize: ControlSize.regular,
                                  child: const Text('Configure Federation...'),
                                  onPressed: () {
                                    context.go('/project/settings');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 32),
                      Text(
                        'Recent Activity',
                        style: MacosTheme.of(context).typography.title2,
                      ),
                      const SizedBox(height: 12),
                      const ActivityTicker(),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final Widget child;

  const StatCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MacosDynamicColor.resolve(
          MacosColors.controlBackgroundColor,
          context,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: MacosColors.systemGrayColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: MacosTheme.of(context).typography.subheadline.copyWith(
              color: MacosColors.systemGrayColor,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class SimpleStatCard extends StatelessWidget {
  final String title;
  final String value;

  const SimpleStatCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return StatCard(
      title: title,
      child: Text(
        value,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class PriorityStatCard extends StatelessWidget {
  final int p0Count;
  final int p1Count;
  final int p2Count;
  final int p3Count;

  const PriorityStatCard({
    super.key,
    required this.p0Count,
    required this.p1Count,
    required this.p2Count,
    required this.p3Count,
  });

  Widget _buildBadge(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: MacosColors.white,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StatCard(
      title: 'Priority Open',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p0Count > 0) ...[
            _buildBadge('P0', p0Count, MacosColors.systemRedColor),
            const SizedBox(width: 12),
          ],
          _buildBadge('P1', p1Count, MacosColors.systemOrangeColor),
          const SizedBox(width: 12),
          _buildBadge('P2', p2Count, MacosColors.systemYellowColor),
          const SizedBox(width: 12),
          _buildBadge('P3', p3Count, MacosColors.systemBlueColor),
        ],
      ),
    );
  }
}
