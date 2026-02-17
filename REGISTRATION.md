# User Registration with Email Verification and Stripe Integration

## Overview

This document describes the new user registration flow that includes email verification and Stripe payment integration.

## Flow Description

1. **User Registration** - User submits registration form with username, email, and password
2. **Email Verification** - User receives verification email and clicks the link
3. **Subscription Page** - After verification, user is redirected to subscription page with Stripe payment link
4. **Account Activation** - After successful payment, user account is fully activated

## Routes

### POST /join
Handles user registration.

**Parameters:**
- `username` (required) - Username (1-31 chars, alphanumeric with _ and -)
- `email` (required) - Valid email address (1-254 chars)
- `password` (required) - Password (8-256 chars)
- `back_to` (optional) - Redirect URL after registration

**Validation:**
- Username must start with a letter and contain only alphanumeric characters, underscores, and hyphens
- Email must be a valid email format
- Password must be between 8-256 characters
- Username must be unique
- Email must be unique

**Response:**
- Redirects to `back_to` parameter (or `/` by default)
- Creates user with `email_verified = 0`
- Sends verification email with 24-hour expiry token
- Flash message: "Account created! Please check your email to verify your account."

### GET /verify-email
Handles email verification.

**Parameters:**
- `token` (required) - Email verification token

**Response:**
- On success: Marks email as verified, creates payment token, redirects to `/subscribe?token={payment_token}`
- On failure: Returns 403 with error message

### GET /subscribe
Displays subscription page with Stripe payment link.

**Parameters:**
- `token` (required) - Payment token

**Response:**
- On success: Renders subscription page with Stripe payment link
- On failure: Returns 403 with error message

## Database Schema

### email_verification_tokens Table
```sql
CREATE TABLE email_verification_tokens (
    token TEXT,
    username TEXT,
    expires INTEGER
);
```

### payment_tokens Table
```sql
CREATE TABLE payment_tokens (
    token TEXT,
    username TEXT,
    created INTEGER
);
```

### users Table (updated)
Added column:
- `email_verified INTEGER DEFAULT 0` - Whether the user's email has been verified

## Models

### Bliptown::Model::EmailVerification
Manages email verification tokens.

**Methods:**
- `create_token({ username => $username })` - Creates a verification token that expires in 24 hours
- `read_token({ token => $token })` - Retrieves a token record
- `delete_token({ token => $token })` - Deletes a token

### Bliptown::Model::PaymentToken
Manages payment tokens for Stripe integration.

**Methods:**
- `create_token({ username => $username })` - Creates a payment token
- `read_token({ token => $token })` - Retrieves a token record
- `delete_token({ token => $token })` - Deletes a token

## Configuration

### Environment Variables

#### Required for Email Sending
If these are not set, verification emails will only be logged (useful for development):

- `BLIPTOWN_SMTP_ADDR` - SMTP server address
- `BLIPTOWN_SMTP_PORT` - SMTP server port
- `BLIPTOWN_SMTP_LOGIN` - SMTP login username
- `BLIPTOWN_SMTP_PASS` - SMTP login password

#### Required for Stripe Integration
- `BLIPTOWN_STRIPE_URL` - Base URL for Stripe payment page (e.g., `https://buy.stripe.com/YOUR_PAYMENT_LINK`)

The payment token is appended as `client_reference_id` parameter to identify the user in Stripe webhooks.

## Security Features

### Password Security
- Passwords are hashed using bcrypt with 2b algorithm and 12 rounds
- Salt is generated using `Mojo::Util::generate_secret`

### Token Security
- All tokens use `Mojo::Util::generate_secret` for cryptographically secure random generation
- Email verification tokens expire after 24 hours
- Payment tokens never expire but can be manually deleted

### 2FA (TOTP)
- TOTP secret is automatically generated during user registration
- Users can set up 2FA in settings after registration

### Email Verification
- Users must verify their email before accessing subscription page
- Verification tokens are single-use (deleted after verification)

## Usage Example

### Registration Form HTML
```html
<form method="POST" action="/join">
    <label>Username:
        <input type="text" name="username" required minlength="1" maxlength="31">
    </label>
    <label>Email:
        <input type="email" name="email" required maxlength="254">
    </label>
    <label>Password:
        <input type="password" name="password" required minlength="8" maxlength="256">
    </label>
    <input type="hidden" name="back_to" value="/">
    <button type="submit">Sign Up</button>
</form>
```

### Testing the Flow

1. Submit registration form
2. Check application logs for verification email (if SMTP not configured)
3. Extract token from verification URL
4. Visit `/verify-email?token={token}`
5. You will be redirected to `/subscribe?token={payment_token}`
6. The Stripe URL will include the payment token as `client_reference_id`

## Testing

Run the registration tests:

```shell-session
$ carton exec -- perl t/registration.t
```

Tests cover:
- User registration validation
- Duplicate username/email checking
- Email verification flow
- Payment token generation
- Subscription page rendering
- Model CRUD operations

## Integration with Stripe

The payment token is passed to Stripe as the `client_reference_id` parameter. This allows you to:

1. Identify which user completed the payment in Stripe webhooks
2. Update user account status after successful payment
3. Track payment status in your application

### Stripe Webhook Setup

When you receive a Stripe webhook for a successful payment, you can:

1. Extract the `client_reference_id` from the webhook payload
2. Look up the payment token in your database
3. Activate the user's account
4. Delete the payment token (optional)

Example webhook handler (to be implemented):

```perl
sub stripe_webhook {
    my $c = shift;
    my $event = $c->req->json;
    
    if ($event->{type} eq 'checkout.session.completed') {
        my $token = $event->{data}{object}{client_reference_id};
        my $record = $c->payment_token->read_token({ token => $token });
        
        if ($record) {
            my $username = $record->{username};
            # Activate user account here
            # Send welcome email, etc.
        }
    }
    
    $c->render(json => { received => 1 });
}
```

## Notes

- The registration flow creates users with `email_verified = 0` initially
- TOTP secret is generated during registration but 2FA is not required until user sets it up
- Payment tokens do not expire and should be cleaned up after payment
- Email verification tokens automatically expire after 24 hours
- In development mode, emails are logged instead of sent (unless SMTP is configured)
