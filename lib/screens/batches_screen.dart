import 'package:flutter/material.dart';
import '../widgets/responsive_container.dart';
import 'package:provider/provider.dart';
import '../providers/edutrack_provider.dart';
import '../models/student.dart';
import '../models/batch.dart';
import '../widgets/stylish_search_bar.dart'; // Import StylishSearchBar
import '../widgets/confirmation_dialog.dart';
import 'student_details_screen.dart'; // Import StudentDetailsScreen
import 'package:page_transition/page_transition.dart';
import '../widgets/fade_in.dart';
import 'edit_batch_screen.dart'; // Import EditBatchScreen
import 'add_students_to_batch_screen.dart'; // Import AddStudentsToBatchScreen
import 'batch_details_screen.dart'; // Import BatchDetailsScreen
import '../services/ad_manager.dart';

class BatchesScreen extends StatefulWidget {
  final int initialFilterIndex;
  const BatchesScreen(
      {super.key, this.initialFilterIndex = 1}); // Default to All Students
  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends State<BatchesScreen>
    with SingleTickerProviderStateMixin {
  String _query = '';
  late int _filterIndex; // 0 All Batches, 1 All Students, 2 Paid, 3 Due
  final Map<String, bool> _expandedState = {}; // Re-add _expandedState
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _filterIndex = widget.initialFilterIndex;
    _tabController = TabController(length: 2, vsync: this);

    // Set initial tab based on filter index
    if (_filterIndex == 0) {
      _tabController.index = 0; // All Batches tab
    } else {
      _tabController.index = 1; // All Students tab
    }

    _tabController.addListener(() {
      if (_tabController.index == 0) {
        // If "All Batches" tab is selected, reset filter to 0
        setState(() {
          _filterIndex = 0;
        });
      } else {
        // If "All Students" tab is selected, ensure a student filter is active (default to All Students)
        if (_filterIndex == 0) {
          setState(() {
            _filterIndex = 1;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();

    if (provider.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Batches'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final searchResults = provider.searchStudentsAndBatches(_query);
    final batches =
        _query.isEmpty ? provider.batches : provider.searchBatches(_query);

    Map<Batch, List<Student>> filteredResults = {};
    // Pre-calculate students for Tab 1 even when on Tab 0 (Batches) to prevent empty flash
    if (_filterIndex == 1 || _filterIndex == 0) {
      filteredResults = searchResults;
    } else {
      searchResults.forEach((batch, students) {
        final filteredStudents = students.where((student) {
          if (_filterIndex == 2) return student.feesPaid;
          if (_filterIndex == 3) return !student.feesPaid;
          return false;
        }).toList();

        if (filteredStudents.isNotEmpty) {
          filteredResults[batch] = filteredStudents;
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: StylishSearchBar(
          hintText: 'Search students or batches',
          onChanged: (v) => setState(() => _query = v),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All Batches'),
            Tab(text: 'All Students'),
          ],
        ),
      ),
      body: ResponsiveContainer(
        maxWidth: 800,
        child: Column(
          children: [
            if (_tabController.index ==
                1) // Only show filters in "All Students" tab
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    FilterChip(
                      label: const Text('All Students'),
                      selected: _filterIndex == 1,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _filterIndex = 1;
                          });
                        }
                      },
                    ),
                    FilterChip(
                      label: const Text('Paid'),
                      selected: _filterIndex == 2,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _filterIndex = 2;
                          });
                        }
                      },
                    ),
                    FilterChip(
                      label: const Text('Due'),
                      selected: _filterIndex == 3,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _filterIndex = 3;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAllBatchesView(batches, provider),
                  _buildSearchResults(filteredResults, provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllBatchesView(List<Batch> batches, EduTrackProvider provider) {
    if (batches.isEmpty) {
      return _EmptyState(
        message: 'No batches found',
        buttonLabel: 'Add New Batch',
        onAdd: () {
          AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
            Navigator.pushNamed(context, '/create-batch');
          });
        },
      );
    }

    return ListView.builder(
      itemCount: batches.length,
      itemBuilder: (context, i) {
        final batch = batches[i];
        final studentsInBatch =
            provider.students.where((s) => s.batchName == batch.name).toList();

        final isExpanded =
            _expandedState[batch.id] ?? false; // Use batch.id for unique key

        return FadeIn(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              child: BatchDetailsScreen(batch: batch),
                            ),
                          );
                        },
                        child: Text(
                          '${batch.name} (${studentsInBatch.length} students)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: batch.postponed
                                  ? Colors.grey
                                  : Colors.deepPurple,
                              decoration: batch.postponed
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: Colors.grey,
                              fontSize: 18),
                        ),
                      ),
                      _buildPopupMenuButton(
                          context, provider, batch, studentsInBatch),
                    ],
                  ),
                  Text('Class: ${batch.studentClass}'),
                  const SizedBox(height: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    constraints: BoxConstraints(
                      maxHeight: isExpanded
                          ? studentsInBatch.length * 60.0 +
                              100 // Add some buffer for full expansion
                          : (studentsInBatch.length > 3
                              ? 3 * 60.0
                              : studentsInBatch.length * 60.0),
                    ),
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: studentsInBatch
                          .take(isExpanded ? studentsInBatch.length : 3)
                          .map((s) => ListTile(
                                dense: true, // Make the list tile more compact
                                title: Text(s.name),
                                subtitle: Text('Class ${s.studentClass}'),
                                onTap: () {
                                  AdManager.instance.showInterstitialIfAllowed(
                                      onAdComplete: () {
                                    Navigator.of(context).push(
                                      PageTransition(
                                        type: PageTransitionType.rightToLeft,
                                        child: StudentDetailsScreen(student: s),
                                      ),
                                    );
                                  });
                                },
                              ))
                          .toList(),
                    ),
                  ),
                  if (studentsInBatch.length > 3)
                    TextButton(
                      onPressed: () {
                        if (isExpanded) {
                          setState(() {
                            _expandedState[batch.id] = false;
                          });
                        } else {
                          AdManager.instance.showInterstitialIfAllowed(
                              onAdComplete: () {
                            Navigator.of(context).push(
                              PageTransition(
                                type: PageTransitionType.rightToLeft,
                                child: BatchDetailsScreen(batch: batch),
                              ),
                            );
                          });
                        }
                      },
                      child: Text(isExpanded ? 'View Less' : 'View All'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResults(
      Map<Batch, List<Student>> results, EduTrackProvider provider) {
    if (results.isEmpty) {
      return _EmptyState(onAdd: () {
        AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
          Navigator.pushNamed(context, '/add-student');
        });
      });
    }

    final batches = results.keys.toList();

    return ListView.builder(
      itemCount: batches.length,
      itemBuilder: (context, index) {
        final batch = batches[index];
        final students = results[batch]!;
        final isExpanded = _expandedState[batch.id] ?? false;

        return FadeIn(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              child: BatchDetailsScreen(batch: batch),
                            ),
                          );
                        },
                        child: Text(
                          '${batch.name} (${students.length} students)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: batch.postponed
                                ? Colors.grey
                                : Colors.deepPurple,
                            decoration: batch.postponed
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: Colors.grey,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      _buildPopupMenuButton(context, provider, batch, students),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    constraints: BoxConstraints(
                      maxHeight: isExpanded
                          ? students.length * 70.0 + 50
                          : (students.length > 3
                              ? 3 * 70.0
                              : students.length * 70.0),
                    ),
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: students
                          .take(isExpanded ? students.length : 3)
                          .map((student) {
                        return ListTile(
                          title: Text(student.name),
                          subtitle: Text('Class ${student.studentClass}'),
                          onTap: () {
                            AdManager.instance.showInterstitialIfAllowed(
                                onAdComplete: () {
                              Navigator.of(context).push(
                                PageTransition(
                                  type: PageTransitionType.rightToLeft,
                                  child: StudentDetailsScreen(student: student),
                                ),
                              );
                            });
                          },
                          trailing: _buildPaidDueButton(student, provider),
                        );
                      }).toList(),
                    ),
                  ),
                  if (students.length > 3)
                    TextButton(
                      onPressed: () {
                        if (isExpanded) {
                          setState(() {
                            _expandedState[batch.id] = false;
                          });
                        } else {
                          AdManager.instance.showInterstitialIfAllowed(
                              onAdComplete: () {
                            Navigator.of(context).push(
                              PageTransition(
                                type: PageTransitionType.rightToLeft,
                                child: BatchDetailsScreen(batch: batch),
                              ),
                            );
                          });
                        }
                      },
                      child: Text(isExpanded ? 'View Less' : 'View All'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaidDueButton(Student student, EduTrackProvider provider) {
    return ElevatedButton(
      onPressed: () {
        AdManager.instance.showInterstitialIfAllowed(onAdComplete: () async {
          final confirmed = await showConfirmationDialog(
            context,
            'Are you sure you want to mark this student as ${student.feesPaid ? 'Due' : 'Paid'}?',
          );
          if (confirmed == true) {
            provider.togglePaymentStatusForMonth(student.id, DateTime.now());
          }
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: student.feesPaid ? Colors.green : Colors.orange,
      ),
      child: Text(student.feesPaid ? 'Paid' : 'Due'),
    );
  }

  void _showPremiumLockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Colors.amber),
            SizedBox(width: 8),
            Text('Premium Feature'),
          ],
        ),
        content: const Text(
            'This feature is available for Premium users only.\n\n'
            'Unlock unlimited students, batch editing, remove students, and remove all ads!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.pushNamed(context, '/subscribe');
            },
            child: const Text('Go Premium'),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupMenuButton(BuildContext context, EduTrackProvider provider,
      Batch batch, List<Student> studentsInBatch) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'edit_batch') {
          if (!provider.isPremium) {
            _showPremiumLockDialog(context);
            return;
          }
          AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
            Navigator.of(context).push(
              PageTransition(
                type: PageTransitionType.rightToLeft,
                child: EditBatchScreen(batch: batch),
              ),
            );
          });
        } else if (value == 'add_student') {
          // Check limit: 15 students per batch for free users
          if (!provider.isPremium && studentsInBatch.length >= 15) {
            _showPremiumLockDialog(context);
            return;
          }

          AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
            Navigator.of(context).push(
              PageTransition(
                type: PageTransitionType.rightToLeft,
                child: AddStudentsToBatchScreen(
                  batchName: batch.name,
                  studentClass: batch.studentClass,
                ),
              ),
            );
          });
        } else if (value == 'postpone_batch') {
          // Postpone feature - Free
          _confirmPostponeBatch(context, provider, batch);
        } else if (value == 'delete_batch') {
          // Delete Batch - Free
          AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
            _confirmDeleteBatch(context, provider, batch);
          });
        } else if (value == 'remove_student') {
          if (!provider.isPremium) {
            _showPremiumLockDialog(context);
            return;
          }
          AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
            _showRemoveStudentDialog(context, provider, batch, studentsInBatch);
          });
        }
      },
      itemBuilder: (BuildContext context) {
        final isPremium = provider.isPremium;
        return <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'edit_batch',
            child: Row(
              children: [
                const Text('Edit Batch'),
                if (!isPremium) const Spacer(),
                if (!isPremium)
                  const Icon(Icons.lock, size: 16, color: Colors.grey),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'add_student',
            child: Row(
              children: [
                const Text('Add Student'),
                if (!isPremium && studentsInBatch.length >= 15) const Spacer(),
                if (!isPremium && studentsInBatch.length >= 15)
                  const Icon(Icons.lock, size: 16, color: Colors.grey),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'postpone_batch',
            child: Text(batch.postponed ? 'Resume Batch' : 'Postpone Batch'),
          ),
          PopupMenuItem<String>(
            value: 'remove_student',
            child: Row(
              children: [
                const Text('Remove Student'),
                if (!isPremium) const Spacer(),
                if (!isPremium)
                  const Icon(Icons.lock, size: 16, color: Colors.grey),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'delete_batch',
            child: Text('Delete Batch', style: TextStyle(color: Colors.red)),
          ),
        ];
      },
    );
  }

  void _confirmPostponeBatch(
      BuildContext context, EduTrackProvider provider, Batch batch) async {
    final isPostponed = batch.postponed;
    final action = isPostponed ? 'Resume' : 'Postpone';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Batch'),
        content: Text(
            'Are you sure you want to ${action.toLowerCase()} this batch? ${!isPostponed ? "It will be hidden from Due Lists." : "It will reappear in Due Lists."}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.toggleBatchPostponed(batch.id, !batch.postponed);
    }
  }

  void _confirmDeleteBatch(
      BuildContext context, EduTrackProvider provider, Batch batch) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Batch'),
          content: Text(
              'Are you sure you want to delete the batch "${batch.name}" and all its students? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                provider.deleteBatch(batch.id);
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showRemoveStudentDialog(BuildContext context, EduTrackProvider provider,
      Batch batch, List<Student> studentsInBatch) {
    Student? selectedStudent;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Remove Student from Batch'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Select a student to remove from "${batch.name}":'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<Student>(
                    initialValue: selectedStudent,
                    decoration:
                        const InputDecoration(labelText: 'Select Student'),
                    items: studentsInBatch.map((student) {
                      return DropdownMenuItem<Student>(
                        value: student,
                        child: Text(student.name),
                      );
                    }).toList(),
                    onChanged: (Student? newValue) {
                      setState(() {
                        selectedStudent = newValue;
                      });
                    },
                    validator: (v) =>
                        (v == null) ? 'Please select a student' : null,
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Dismiss the dialog
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (selectedStudent != null) {
                      provider.deleteStudent(selectedStudent!
                          .id); // Assuming deleteStudent removes from the global list
                      Navigator.of(context).pop(); // Dismiss the dialog
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Remove'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final String message;
  final String buttonLabel;

  const _EmptyState({
    required this.onAdd,
    this.message = 'No students found',
    this.buttonLabel = 'Add Student',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.groups, size: 64, color: Colors.grey),
        const SizedBox(height: 8),
        Text(message),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: onAdd, child: Text(buttonLabel)),
      ]),
    );
  }
}
