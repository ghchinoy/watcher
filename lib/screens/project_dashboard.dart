import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
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
      builder: (context) => MacosSheet(
        child: PlannerModal(project: appState.selectedProject!),
      ),
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
                  child: ProgressCircle(),
                ),
              ),
            ],
          );
        }

        if (appState.error != null) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Dashboard'),
              actions: [
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
                  child: Text('Error: ${appState.error}'),
                ),
              ),
            ],
          );
        }

        final issues = appState.currentIssues;
        final openCount = issues.where((i) => i.status == 'open').length;
        final inProgressCount = issues.where((i) => i.status == 'in_progress').length;
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
                      Row(
                        children: [
                          _buildStatCard(context, 'Total Issues', issues.length.toString()),
                          const SizedBox(width: 16),
                          _buildStatCard(context, 'Open', openCount.toString()),
                          const SizedBox(width: 16),
                          _buildStatCard(context, 'In Progress', inProgressCount.toString()),
                          const SizedBox(width: 16),
                          _buildStatCard(context, 'Closed', closedCount.toString()),
                        ],
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

  Widget _buildStatCard(BuildContext context, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MacosDynamicColor.resolve(CupertinoColors.systemGrey6, context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
