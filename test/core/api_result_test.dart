import 'package:checkers/core/network/api_error.dart';
import 'package:checkers/core/network/api_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiResult', () {
    test('Success maps through when()', () {
      const ApiResult<int> result = Success(42);
      final value = result.when(
        success: (data) => 'ok:$data',
        failure: (error) => 'err:${error.code}',
      );
      expect(value, 'ok:42');
    });

    test('Failure maps through when()', () {
      const ApiResult<int> result = Failure(
        ApiError(code: 'boom', message: 'went wrong'),
      );
      final value = result.when(
        success: (data) => 'ok:$data',
        failure: (error) => 'err:${error.code}',
      );
      expect(value, 'err:boom');
    });
  });
}
