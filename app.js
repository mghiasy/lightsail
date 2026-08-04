const AWS_LOGIN_URL = "https://ghtsail.aws.amazon.com/ls/webapp/home/";

const loginButton = document.getElementById("aws-login");

loginButton.addEventListener("click", () => {
  window.location.assign(AWS_LOGIN_URL);
});
