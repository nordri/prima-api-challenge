from user_management.user_routes import allowed_file, validate_user_data


def test_validate_user_data_success():
    error, status = validate_user_data(
        {
            "name": "Test User",
            "email": "test@example.com",
        }
    )

    assert error is None
    assert status is None


def test_validate_user_data_missing_email():
    error, status = validate_user_data(
        {
            "name": "Test User",
        }
    )

    assert error == "Missing required data: email"
    assert status == 400


def test_allowed_file():
    assert allowed_file("avatar.png") is True
    assert allowed_file("avatar.jpg") is True
    assert allowed_file("avatar.exe") is False
