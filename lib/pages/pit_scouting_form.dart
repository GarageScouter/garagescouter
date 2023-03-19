import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:provider/provider.dart';
import 'package:robotz_garage_scouting/components/forms/conditional_hidden_input.dart';
import 'package:robotz_garage_scouting/components/forms/radio_helpers.dart';
import 'package:robotz_garage_scouting/components/forms/conditional_hidden_field.dart';
import 'package:robotz_garage_scouting/pages/home_page.dart';
import 'package:robotz_garage_scouting/utils/dataframe_helpers.dart';
import 'package:robotz_garage_scouting/utils/file_io_helpers.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:ml_dataframe/ml_dataframe.dart';
import 'package:path/path.dart' as p;
import 'package:robotz_garage_scouting/validators/custom_integer_validators.dart';

import 'package:robotz_garage_scouting/models/retain_info_model.dart';
import 'package:robotz_garage_scouting/utils/hash_helpers.dart';
import 'package:robotz_garage_scouting/validators/custom_text_validators.dart';

class FormsTest extends StatefulWidget {
  const FormsTest({super.key});

  @override
  State<FormsTest> createState() => _FormsTestState();
}

class _FormsTestState extends State<FormsTest> {
  void _navigateToSecondPage() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => const MyHomePage(
              title: 'Home page',
            )));
  }

  final _formKey = GlobalKey<FormBuilderState>();

  final double questionFontSize = 10;

  void _kSuccessMessage(File value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(
          "Successfully wrote file ${value.path}",
          textAlign: TextAlign.center,
        )));
  }

  void _kFailureMessage(error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(
          error.toString(),
          textAlign: TextAlign.center,
        )));
  }

  /// Handles form submission
  Future<void> submitForm() async {
    ScaffoldMessenger.of(context).clearSnackBars();
    bool isValid = _formKey.currentState!.saveAndValidate();

    if (!isValid) {
      _kFailureMessage(
          "One or more fields are invalid. Review your inputs and try submitting again.");
      return;
    }

    // check if the "drive_train" is not set to other and if it isn't,
    // delete the contents of the "other_drive_train" column.
    if (_formKey.currentState?.value["drive_train"] != "Other") {
      _formKey.currentState?.patchValue({"other_drive_train": ""});
      _formKey.currentState?.save();
    }

    // Help clean up the input by removing spaces on both ends of the string
    Map<String, dynamic> trimmedInputs =
        _formKey.currentState!.value.map((key, value) {
      return (value is String)
          ? MapEntry(key, value.trim())
          : MapEntry(key, value);
    });

    _formKey.currentState?.patchValue(trimmedInputs);
    _formKey.currentState?.save();

    DataFrame df = convertFormStateToDataFrame(_formKey.currentState!);

    // adds timestamp
    df = df.addSeries(Series("timestamp", [DateTime.now().toString()]));

    final String teamNumber =
        _formKey.currentState!.value["team_number"] ?? "no_team_number";

    final String filePath = await generateUniqueFilePath(
        extension: "csv", prefix: "${teamNumber}_pit_scouting");

    final File file = File(filePath);

    try {
      File finalFile = await file.writeAsString(convertDataFrameToString(df));

      saveFileToDevice(finalFile).then((File file) {
        context.read<RetainInfoModel>().resetPitScouting();
        _formKey.currentState?.reset();
        _kSuccessMessage(file);
      }).catchError(_kFailureMessage);
    } on Exception catch (_, exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
        log(exception.toString(), name: "ERROR");
      }
    }
  }

  /// Helper to update Form State for other form elements that are dependent on state
  void _saveFormState(value) {
    setState(() {
      _formKey.currentState?.save();
    });
  }

  /// Determines if we can show the "Other Drive Train Field"
  /// We want to show it under one of two situations:
  /// 1. The user selected "Other" for "drive_train"
  /// 2. It is the first render and the user had selected
  ///    "Other" previously for "drive_train"
  bool _canShowFieldFromMatch(pitData,
      {String key = "drive_train", String match = "Other"}) {
    // const String key = "drive_train";
    // const String match = "Other";
    final String current = _formKey.currentState?.value[key] ?? "";

    // On the first load, the currentState will be empty, so we need
    // to check if it's empty, but after that we can assume we check
    // the current field value.
    if (current.isNotEmpty && current != match) {
      return false;
    }

    // Otherwise just find if either contains the match.
    return [current, pitData[key].toString()].contains(match);
  }

  /// This is a fairly hacky workaround to work around form fields that aren't
  /// immediately shown on the screen. For Pit Scouting, the "Other Drive Train"
  /// field. We wait for the file system to complete and then reset/save the form.
  Future<void> _clearForm(RetainInfoModel retain) async {
    _formKey.currentState?.save();
    final Map<String, dynamic> blanks =
        convertListToDefaultMap(_formKey.currentState?.value.keys);
    await retain.setPitScouting(blanks);
    setState(() {
      _formKey.currentState?.patchValue(blanks);
      _formKey.currentState?.save();
    });
  }

  /// We use the deactivate life-cycle hook since State is available and we can
  /// read it to optionally save to the "RetainInfoModel" object if the user has
  /// specified they want to retain info in the form when they back out.
  @override
  void deactivate() {
    RetainInfoModel model = context.watch<RetainInfoModel>();
    if (model.doesRetainInfo()) {
      _formKey.currentState?.save();
      model.setPitScouting(_formKey.currentState!.value);
    }
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetainInfoModel>(builder: (context, retain, _) {
      return Scaffold(
          appBar: AppBar(
            title: const Text(
              "Pit Scouting Form",
              textAlign: TextAlign.center,
            ),
            actions: retain.doesRetainInfo()
                ? [
                    IconButton(
                      onPressed: () {
                        showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                                    title:
                                        const Text("Clear Pit Scouting Data"),
                                    content: const Text(
                                        "Are you sure you want to clear Pit Scouting Data?\n\n"
                                        "Your temporary data will also be cleared."),
                                    actionsAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    actions: [
                                      OutlinedButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text("Cancel"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await _clearForm(retain);
                                          Navigator.pop(context);
                                        },
                                        child: const Text("Confirm"),
                                      )
                                    ]));
                      },
                      icon: const Icon(Icons.clear),
                      tooltip: "Clear Pit Scouting Form",
                    )
                  ]
                : [],
          ),
          body: CustomScrollView(slivers: <Widget>[
            SliverToBoxAdapter(
              child: Column(
                children: [
                  FormBuilder(
                      key: _formKey,
                      child: Consumer<RetainInfoModel>(
                        builder: (context, model, _) {
                          final Map<String, dynamic> pitData =
                              model.pitScouting();
                          return Column(
                            children: <Widget>[
                              const Divider(),
                              const Text("General Questions"),
                              const Divider(),

                              FormBuilderTextField(
                                name: "team_name",
                                initialValue: pitData['team_name'] ?? "",
                                decoration: const InputDecoration(
                                    labelText: "What is the Team Name?",
                                    prefixIcon: Icon(Icons.abc)),
                                textInputAction: TextInputAction.next,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                  CustomTextValidators.doesNotHaveCommas(),
                                ]),
                              ),
                              FormBuilderTextField(
                                name: "team_number",
                                initialValue: pitData['team_number'],
                                decoration: const InputDecoration(
                                    labelText: "What is the Team Number?",
                                    prefixIcon: Icon(Icons.numbers)),
                                textInputAction: TextInputAction.next,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                  FormBuilderValidators.integer(),
                                  CustomTextValidators.doesNotHaveCommas(),
                                  CustomIntegerValidators.notNegative()
                                ]),
                              ),
                              FormBuilderChoiceChip(
                                  name: "drive_train",
                                  initialValue: pitData['drive_train'],
                                  decoration: const InputDecoration(
                                      labelText:
                                          "What kind of Drive Train do they have?",
                                      prefixIcon: Icon(Icons.drive_eta)),
                                  onChanged: _saveFormState,
                                  validator: FormBuilderValidators.required(),
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  options: [
                                    "Tank Drive",
                                    "West Coast",
                                    "Swerve Drive",
                                    "Other"
                                  ]
                                      .map((option) => FormBuilderChipOption(
                                          value: option,
                                          child: Text(
                                            option,
                                            style:
                                                const TextStyle(fontSize: 14),
                                          )))
                                      .toList(growable: false)),
                              ConditionalHiddenTextField(
                                name: "other_drive_train",
                                initialValue: pitData["other_drive_train"],
                                showWhen: _canShowFieldFromMatch(pitData),
                              ),
                              YesOrNoAnswers(
                                name: "has_arm",
                                label: "Do they have an arm?",
                                initialValue: pitData['has_arm'],
                                validators: FormBuilderValidators.required(),
                                onChanged: _saveFormState,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                              ),
                              YesOrNoAnswers(
                                name: "has_intake",
                                label: "Do they have an intake system?",
                                initialValue: pitData['has_intake'],
                                validators: FormBuilderValidators.required(),
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                              ),

                              const Divider(),
                              const Text("Autonomous Questions"),
                              const Divider(),

                              YesOrNoAnswers(
                                name: "has_autonomous",
                                label: "Do they have autonomous?",
                                initialValue: pitData['has_autonomous'],
                                validators: FormBuilderValidators.required(),
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                onChanged: _saveFormState,
                              ),
                              ConditionalHiddenField(
                                showWhen: _canShowFieldFromMatch(pitData,
                                    key: "has_autonomous", match: "yes"),
                                child: YesOrNoAnswers(
                                  name: "can_charge_autonomous",
                                  label:
                                      "Are they able to use the charge station in autonomous?",
                                  initialValue:
                                      pitData['can_charge_autonomous'],
                                  validators: FormBuilderValidators.required(),
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                ),
                              ),
                              // ConditionalHiddenField(
                              //     showWhen: _canShowFieldFromMatch(pitData,
                              //         key: "has_autonomous", match: "yes"),
                              //     child: FormBuilderDropdown(
                              //       name: "field_position",
                              //       decoration: const InputDecoration(
                              //           labelText:
                              //               "Autonomous Starting Position",
                              //           prefixIcon: Icon(Icons.map)),
                              //       validator: FormBuilderValidators.required(),
                              //       autovalidateMode:
                              //           AutovalidateMode.onUserInteraction,
                              //       items: ["Center", "Bump", "Lane"]
                              //           .map((e) => DropdownMenuItem(
                              //               value: e,
                              //               child: Text(e.toString())))
                              //           .toList(),
                              //       initialValue: pitData["field_position"],
                              //     )),
                              ConditionalHiddenField(
                                  showWhen: _canShowFieldFromMatch(pitData,
                                      key: "has_autonomous", match: "yes"),
                                  child: FormBuilderCheckboxGroup(
                                    name: "auto_starting_positions",
                                    initialValue:
                                        pitData['auto_starting_positions'],
                                    decoration: const InputDecoration(
                                        labelText:
                                            "Where do they start in Autonomous?"),
                                    options: ["Center", "Bump", "Lane"]
                                        .map((e) => FormBuilderFieldOption(
                                            value: e.toString()))
                                        .toList(),
                                  )),
                              ConditionalHiddenField(
                                showWhen: _canShowFieldFromMatch(pitData,
                                    key: "has_autonomous", match: "yes"),
                                child: FormBuilderTextField(
                                  name: "auto_notes",
                                  initialValue: pitData['auto_notes'],
                                  decoration: const InputDecoration(
                                      labelText: "Autonmous Notes (if needed)?",
                                      prefixIcon: Icon(Icons.note)),
                                  textInputAction: TextInputAction.next,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  validator: FormBuilderValidators.compose([
                                    CustomTextValidators.doesNotHaveCommas(),
                                  ]),
                                ),
                              ),

                              const Divider(),
                              const Text("Teleop Questions"),
                              const Divider(),

                              FormBuilderCheckboxGroup(
                                name: "teleop_score_cones",
                                initialValue: pitData['teleop_score_cones'],
                                decoration: const InputDecoration(
                                    icon: Icon(Icons.score),
                                    labelText:
                                        "Can they score Cones in Teleop?"),
                                options: ["Low", "Mid", "High"]
                                    .map((e) => FormBuilderFieldOption(
                                        value: e.toString()))
                                    .toList(),
                              ),
                              FormBuilderCheckboxGroup(
                                name: "teleop_score_cubes",
                                initialValue: pitData['teleop_score_cubes'],
                                decoration: const InputDecoration(
                                    icon: Icon(Icons.score),
                                    labelText:
                                        "Can they score Cubes in Teleop?"),
                                options: ["Low", "Mid", "High"]
                                    .map((e) => FormBuilderFieldOption(
                                        value: e.toString()))
                                    .toList(),
                              ),

                              FormBuilderTextField(
                                name: "teleop_notes",
                                initialValue: pitData['teleop_notes'],
                                decoration: const InputDecoration(
                                    labelText: "Teleop Notes (if needed)?",
                                    prefixIcon: Icon(Icons.note)),
                                textInputAction: TextInputAction.next,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: FormBuilderValidators.compose([
                                  CustomTextValidators.doesNotHaveCommas(),
                                ]),
                              ),

                              const Divider(),
                              const Text("Endgame Questions"),
                              const Divider(),
                              YesOrNoAnswers(
                                icon: Icons.balance,
                                name: "endgame_balance",
                                label: "Can they balance in autonomous?",
                                initialValue: pitData['endgame_balance'],
                                validators: FormBuilderValidators.required(),
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                              ),

                              const Divider(),

                              FormBuilderTextField(
                                name: "notes",
                                initialValue: pitData['notes'],
                                decoration: const InputDecoration(
                                    labelText: "Notes (if needed)?",
                                    prefixIcon: Icon(Icons.note)),
                                textInputAction: TextInputAction.next,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: FormBuilderValidators.compose([
                                  CustomTextValidators.doesNotHaveCommas(),
                                ]),
                              ),
                            ],
                          );
                        },
                      )),
                  ElevatedButton(
                      onPressed: submitForm, child: const Text("Submit"))
                ],
              ),
            )
          ]));
    });
  }
}
