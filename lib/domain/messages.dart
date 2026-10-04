const motivationalMessages = [
  'A few reps now, a stronger you later.',
  'Your future self says thanks.',
  'Small moves add up. Go!',
  'Shake off the desk slump.',
  'One set. That is all it takes.',
  'Consistency beats intensity.',
  'Get the blood flowing!',
  'You have got this. Down and give me some.',
  'Break the sitting streak.',
  'Do it before you talk yourself out of it.',
];

/// Picks a message deterministically so the same scheduled slot always shows
/// the same text, while consecutive slots rotate.
String motivationalMessageFor(int seed) =>
    motivationalMessages[seed.abs() % motivationalMessages.length];
