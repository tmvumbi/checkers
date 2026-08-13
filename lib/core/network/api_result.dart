import 'api_error.dart';

sealed class ApiResult<T> {
  const ApiResult();

  R when<R>({
    required R Function(T data) success,
    required R Function(ApiError error) failure,
  }) {
    return switch (this) {
      Success<T>(:final data) => success(data),
      Failure<T>(:final error) => failure(error),
    };
  }
}

final class Success<T> extends ApiResult<T> {
  const Success(this.data);

  final T data;
}

final class Failure<T> extends ApiResult<T> {
  const Failure(this.error);

  final ApiError error;
}
