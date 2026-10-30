package com.asdp.juprovider.exception;

import com.asdp.juprovider.core.action.exception.ActionException;
import com.asdp.juprovider.core.security.PermissionDeniedException;
import com.asdp.juprovider.dto.ApiResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class GlobalExceptionHandler {

    /** Action 오류 계약 (결정 AC5): 400 VALIDATION / 404 NOT_FOUND / 409 CONFLICT / 501 NOT_IMPLEMENTED */
    @ExceptionHandler(ActionException.class)
    public ResponseEntity<ApiResponse<Void>> handleAction(
            ActionException exception) {
        return ResponseEntity.status(exception.getStatus())
                .body(ApiResponse.error(
                        exception.getCode(),
                        exception.getMessage(),
                        exception.getErrors()));
    }

    /** 매핑되지 않은 경로 → 404 (이전에는 500으로 응답됨) */
    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNoResource(
            NoResourceFoundException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error("NOT_FOUND", "요청한 경로가 없습니다.", null));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<Void>> handleBadRequest(
            IllegalArgumentException exception) {
        return ResponseEntity.badRequest()
                .body(ApiResponse.error("BAD_REQUEST", exception.getMessage(), null));
    }

    /** 로그인 실패 등 인증 실패 */
    @ExceptionHandler(AuthenticationFailedException.class)
    public ResponseEntity<ApiResponse<Void>> handleAuthenticationFailed(
            AuthenticationFailedException exception) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ApiResponse.error("UNAUTHORIZED", exception.getMessage(), null));
    }

    /** Core 권한 검사 실패 (Menu Action 실행 권한 없음 등) */
    @ExceptionHandler(PermissionDeniedException.class)
    public ResponseEntity<ApiResponse<Void>> handlePermissionDenied(
            PermissionDeniedException exception) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(ApiResponse.error("FORBIDDEN", exception.getMessage(), null));
    }

    /** 요청 DTO 검증(@Valid) 실패 */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidation(
            MethodArgumentNotValidException exception) {
        FieldError error = exception.getBindingResult().getFieldError();
        String message = error == null
                ? "요청 값이 올바르지 않습니다."
                : error.getField() + ": " + error.getDefaultMessage();
        return ResponseEntity.badRequest()
                .body(ApiResponse.error("VALIDATION", message, null));
    }

    /** 요청 본문(JSON) 형식 오류 */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnreadable(
            HttpMessageNotReadableException exception) {
        return ResponseEntity.badRequest()
                .body(ApiResponse.error("BAD_REQUEST", "요청 형식이 올바르지 않습니다.", null));
    }

    /** 지원하지 않는 HTTP 메서드 → 405 + Allow (C4 실서버 검증 3-7) */
    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ApiResponse<Void>> handleMethodNotSupported(
            HttpRequestMethodNotSupportedException exception) {
        ResponseEntity.BodyBuilder builder = ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED);
        if (exception.getSupportedHttpMethods() != null) {
            builder.allow(exception.getSupportedHttpMethods().toArray(new org.springframework.http.HttpMethod[0]));
        }
        return builder.body(ApiResponse.error("METHOD_NOT_ALLOWED", "지원하지 않는 요청 방식입니다.", null));
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ApiResponse<Void> handleException(Exception e) {
        e.printStackTrace();
        return ApiResponse.error(
                "INTERNAL_ERROR",
                "서버 처리 중 오류가 발생했습니다.",
                null);
    }
}
