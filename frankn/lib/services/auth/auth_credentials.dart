/// Pure data models for authentication contracts in Frankn.
class AuthChallenge {
  final String challenge;
  final String salt;
  final int timestamp;

  const AuthChallenge({
    required this.challenge,
    required this.salt,
    required this.timestamp,
  });
}

class AuthResponse {
  final String response;

  const AuthResponse(this.response);
}

class DerivedCredential {
  final String password;
  final String salt;
  final String argon2Hash;

  const DerivedCredential({
    required this.password,
    required this.salt,
    required this.argon2Hash,
  });
}
