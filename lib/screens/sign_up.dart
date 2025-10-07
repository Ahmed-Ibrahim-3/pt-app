import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/providers/auth_provider.dart';
import '/providers/profile_provider.dart';
import '/models/user_settings.dart';
import '/providers/settings_provider.dart';

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});
  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController(); 
  final _weight = TextEditingController(); 
  String _gender = 'male';
  String _activity = 'moderate';
  String _experience = 'beginner';
  bool _busy = false;
  String? _error;

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  int? _parseInt(String s) => int.tryParse(s.trim());
  double? _parseDouble(String s) => double.tryParse(s.trim());

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authServiceProvider);
    final profiles = ref.read(userSettingsProvider);

    Future<void> create() async {
      if (!_formKey.currentState!.validate()) return;
      if (_password.text != _confirm.text) {
        setState(() => _error = 'Passwords do not match');
        return;
      }
      final age = _parseInt(_age.text);
      final height = _parseDouble(_height.text);
      final weight = _parseDouble(_weight.text);
      if (age == null || height == null || weight == null) {
        setState(() => _error = 'Age/height/weight must be numbers');
        return;
      }

      setState(() { _busy = true; _error = null; });
      try {
        final cred = await auth.createAccount(_email.text.trim(), _password.text);

        await cred.user!.updateDisplayName(_name.text.trim());

        profiles;

         final settings = UserSettings(
          name: _name.text.trim(),
          gender: _gender == 'male' ? Gender.male : Gender.female,
          ageYears: age,
          heightCm: height,                     
          weightKg: weight,                     
          goal: Goal.maintain,                  
          units: Units.metric,                  
          activity: ActivityLevel.values.firstWhere((a) => a.name == _activity),
          experience: ExperienceLevel.values.firstWhere((a) => a.name == _experience)
        );
      await ref.read(settingsProvider.notifier).save(settings);
      await FirebaseAuth.instance.currentUser?.updateDisplayName(settings.name);


      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      } catch (e) {
        setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),

                Row( 
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: _req,
                      ),
                    ),
                    const SizedBox(width: 12), 
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender (at birth)'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(value: 'female', child: Text('Female')),
                        ],
                        onChanged: (v) => setState(() => _gender = v ?? 'male'),
                      ),
                    ),
                  ]
                ),
        
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _activity,
                      decoration: const InputDecoration(labelText: 'Activity *'),
                      items: const [
                        DropdownMenuItem(value: 'sedentary', child: Text('Sedentary')),
                        DropdownMenuItem(value: 'light', child: Text('Light')),
                        DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(value: 'veryActive', child: Text('Very active')),
                      ],
                      onChanged: (v) => setState(() => _activity = v ?? 'moderate'),
                    ),
                  ),
                  const SizedBox(width: 12), 
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _experience,
                      decoration: const InputDecoration(labelText: 'Experience **'),
                      items: const [ 
                        DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
                        DropdownMenuItem(value: 'novice', child: Text('Novice')),
                        DropdownMenuItem(value: 'intermediate', child: Text('Intermediate')),
                        DropdownMenuItem(value: 'advanced', child: Text('Advanced')),
                        DropdownMenuItem(value: 'expert', child: Text('Expert')),
                      ],
                      onChanged: (v) => setState(() => _experience = v ?? 'beginner'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _age,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age (years)'),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _height,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Height (cm)'),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _weight,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                validator: _req,
              ),
              const Divider(height: 32),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password (min 6 chars)'),
                validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password'),
                validator: _req,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : create,
                child: _busy ? const CircularProgressIndicator() : const Text('Create account'),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('*\n Sedentary : 0 hours/week \n Light Activity : 0 - 2.5 hr/wk \n Moderate Activity : 2.5-5 hr/wk \n Active : 5-7.5 hr/wk \n Very Active : 7.5+ hr/wk'),
                  Text('**\n Beginner : <6 months \n Novice : 6 - 18 months \n Intermediate : 1.5 - 3 years \n Advanced : 3 - 5 years \n Expert : 5+ years'),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
