import 'package:flutter_test/flutter_test.dart';
import 'package:frankn/utils/dc_msg_util.dart';

void main() {
  test('OPAQUE wire messages correlate each step to one login attempt', () {
    const attemptId = 'attempt-5c5ca2e1';
    const request = 'client-request-bytes';
    const response = 'server-response-bytes';
    const finalization = 'client-finalization-bytes';

    expect(
      ClientMsgOpaqueStart(attemptId: attemptId, request: request).toJson(),
      {
        'type': 'auth_opaque_start',
        'attempt_id': attemptId,
        'request': request,
      },
    );
    expect(
      HostMessage.fromJson({
        'type': 'auth_opaque_response',
        'attempt_id': attemptId,
        'response': response,
        'timestamp': 1,
      }),
      isA<HostMsgOpaqueResponse>()
          .having((msg) => msg.attemptId, 'attempt id', attemptId)
          .having((msg) => msg.response, 'response', response),
    );
    expect(
      ClientMsgOpaqueFinish(
        attemptId: attemptId,
        finalization: finalization,
      ).toJson(),
      {
        'type': 'auth_opaque_finish',
        'attempt_id': attemptId,
        'finalization': finalization,
      },
    );
    expect(
      HostMessage.fromJson({
        'type': 'auth_success',
        'attempt_id': attemptId,
        'home_dir': '/home/test',
        'timestamp': 2,
      }),
      isA<HostMsgAuthSuccess>().having(
        (msg) => msg.attemptId,
        'attempt id',
        attemptId,
      ),
    );
  });
}
