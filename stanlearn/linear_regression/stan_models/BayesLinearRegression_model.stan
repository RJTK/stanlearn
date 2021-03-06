/*
 * A simple linear regression model with normal priors on
 * the coeficients.  I'm using fairly thin tailed priors,
 * so the data should be scaled to unit variance before fitting.
 */

data {
  int<lower=1> N;  // Number of examples
  int<lower=1> M;  // Number of features

  matrix[N, M] X;  // regressors
  vector[N] y;  // target
}

transformed data {
  matrix[N, M] Q;
  matrix[M, M] R;
  matrix[M, M] R_inv;

  Q = qr_thin_Q(X) * sqrt(N - 1);
  R = qr_thin_R(X) / sqrt(N - 1);
  R_inv = inverse(R);
}

parameters {
  real y0;  // The intercept
  real<lower=0, upper=pi() / 2> unif_nu;  // reparameterization for nu

  vector[M] theta;  // model coefficients in Q space
  real<lower=0> sigma;  // noise term
  real<lower=0> lam;  // theta space magnitude of coefficients
}

transformed parameters{
  real nu;  // output dof
  nu = 2 + tan(unif_nu);  // half-cauchy
}

model {
  y0 ~ normal(0, 1);

  unif_nu ~ uniform(0, pi() / 2);
  sigma ~ std_normal();  // half-normal
  lam ~ exponential(1);
  theta ~ normal(0, lam);
  y ~ student_t(nu, y0 + Q * theta, sigma);
}

generated quantities{
  vector[M] beta;  // model coefficients
  beta = R_inv * theta;
}
