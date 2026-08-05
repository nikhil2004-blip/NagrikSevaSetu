// src/middleware/errorHandler.js
// ─────────────────────────────────────────────────────────────
// Global Error Handler Middleware
//
// In Express, if you call next(error) from any middleware or
// controller, Express skips all remaining regular middleware
// and jumps to this error handler.
//
// Why is this important?
//   Without a centralized error handler, every controller would
//   need its own try/catch block that sends a response. If you
//   forget one, the server crashes or hangs.
//
//   With this, ANY unhandled error anywhere in the app is
//   caught here and returns a clean, consistent JSON response.
//
// Different environments get different info:
//   - In 'development': We send the full error stack so you can
//     debug quickly in the console.
//   - In 'production': We NEVER send the stack trace. It could
//     leak sensitive info about your server structure.
// ─────────────────────────────────────────────────────────────

/**
 * Global error handling middleware.
 * IMPORTANT: Must have 4 parameters (err, req, res, next) for Express to
 * recognize it as an error handler.
 */
const errorHandler = (err, req, res, _next) => {
  // Log every error server-side for debugging
  console.error(`[ERROR] ${req.method} ${req.path}:`, err);

  // Default status code
  let statusCode = err.statusCode || err.status || 500;
  let message = err.message || 'Internal Server Error';

  // Handle CORS errors (Fix B7)
  if (err.message && err.message.startsWith('CORS: Origin')) {
    statusCode = 403;
    message = 'Forbidden: Cross-Origin request blocked.';
  }

  // Handle Mongoose Validation Errors (e.g., required field missing)
  if (err.name === 'ValidationError') {
    statusCode = 400;
    const errors = Object.values(err.errors).map((e) => ({
      field: e.path,
      message: e.message,
    }));
    return res.status(statusCode).json({
      success: false,
      message: 'Database validation failed',
      errors,
    });
  }

  // Handle Mongoose Duplicate Key Error (e.g., duplicate email)
  if (err.code === 11000) {
    statusCode = 409; // Conflict
    const field = Object.keys(err.keyValue)[0];
    message = `A record with this ${field} already exists.`;
  }

  // Handle Mongoose Cast Error (e.g., invalid MongoDB ObjectId format)
  if (err.name === 'CastError') {
    statusCode = 400;
    message = `Invalid ${err.path}: "${err.value}" is not a valid ID format.`;
  }

  const response = {
    success: false,
    message,
  };

  // In development, include the full stack trace for debugging
  if (process.env.NODE_ENV === 'development') {
    response.stack = err.stack;
  }

  res.status(statusCode).json(response);
};

/**
 * 404 Not Found handler.
 * This runs when no route matches the incoming request.
 */
const notFound = (req, res, next) => {
  const error = new Error(`Route not found: ${req.method} ${req.originalUrl}`);
  error.statusCode = 404;
  next(error); // Pass to errorHandler above
};

module.exports = { errorHandler, notFound };
