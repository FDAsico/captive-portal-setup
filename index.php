<?php
// Get the device IP
function get_client_ip() {
    // This is a basic way to get the IP in a LAN setup.
    // Consider more robust methods in a production environment.
    if (isset($_SERVER['REMOTE_ADDR'])) {
        return $_SERVER['REMOTE_ADDR'];
    }
    return '0.0.0.0';
}

$client_ip = get_client_ip();

// --- ETHICAL HACKING LOGIC: SESSION AND DATA HANDLING ---
session_start();
setcookie(session_name(), session_id(), time() + 300, "/");

if ($_SERVER['REQUEST_METHOD'] === 'POST' && $client_ip != '0.0.0.0') {
    $command = "sudo ipset -exist add allowed_clients " . escapeshellarg($client_ip) . " timeout 300";
    exec($command, $output, $return_var);
    if ($return_var === 0) {
        // Success: Redirect user to a landing page or the web
        // This redirect should happen AFTER ipset is updated
        header("Location: success.html"); // Redirect to a success page or intended destination
        file_put_contents('/var/www/html/submissions.log', date("c") . " SUBMITTED\n", FILE_APPEND | LOCK_EX);
        exit("Login successful. You have 90 seconds of internet access. Redirecting...");
    } else {
        error_log("Failed to grant access for IP $client_ip. IPset command failed: " . implode(" ", $output));
        echo "Failed to grant access. An error occurred.";
    }
}
?>

<!DOCTYPE html>
<!-- saved from url=(0097)http://172.16.24.0:8002/index.php?zone=lhubcaptiveportal&redirurl=http%3A%2F%2Fmsftconnect.com%2F -->
<html lang="en"><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ADNU Learning Hub</title>
  <style>
    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      font-family: Arial, sans-serif;
	    background: url("background.jpg") no-repeat center center fixed;
      background-size: cover;
      background-position: center;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
    }

    .overlay {
      background: rgba(241, 201, 87, 0.60);
      border-radius: 50px;
      padding: 40px 30px;
      width: 650px;
      max-width: 90%;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.2);
      text-align: center;
    }

    .logo {
      width: 300px;
      margin-bottom: 20px;
    }

    .title {
      font-size: 26px;
      color: #002d72;
      font-weight: bold;
    }

    .subtitle {
      font-size: 18px;
      color: #002d72;
      font-weight: bold;
      margin-bottom: 25px;
    }

    .input {
      width: 50%;
      padding: 15px;
      margin: 5px 0;
      border: 1px solid #ccc;
      border-radius: 5px;
      font-size: 14px;
	  text-align: center;
    }

    .checkbox-container {
      text-align: center;
      margin-top: 10px;
    }

    .login-btn {
      background-color: #002d72;
      color: white;
      border: none;
      padding: 12px;
      border-radius: 8px;
      width: 40%;
      font-size: 16px;
      margin-top: 20px;
	  margin-bottom: 10px;
      cursor: pointer;
    }

    .footer {
      margin-top: 30px;
      font-size: 12px;
      color: #003366;
	  margin-top: 40px;
    }

    .footer img {
      max-width: 250px;
      height: auto;
	  align: center;
    }

    .terms {
      font-size: 12px;
    }

    /* Media Query for Smaller Screens */
    @media (max-width: 480px) {
      .title {
        font-size: 1.4rem;
      }

      .subtitle {
        font-size: 1rem;
      }

      .input,
      .login-btn {
        width: 100%;
      }

      .overlay {
        padding: 20px 15px;
      }

      .logo {
        width: 80%;
      }
    }
  </style>
</head>
<body>
  <div class="overlay">
    <img src="logo.png" alt="ADNU Logo" class="logo">

    <form method="post" action="">
      <input name="auth_user" class="input" placeholder="Gbox Email Address" required=""><br>
      <input name="auth_pass" type="password" class="input" placeholder="ID Number (e.g. CO201803648)" required=""><br>

      <div class="checkbox-container">
        <input type="checkbox" required="">
        <label class="terms"> I accept the Terms of Service</label>
      </div>

      <input type="submit" class="login-btn" name="accept" value="Login">
    </form>
  </div>

  <div class="footer">
	<img src="footer.png" alt="Footer Logo">
  </div>


</body></html>