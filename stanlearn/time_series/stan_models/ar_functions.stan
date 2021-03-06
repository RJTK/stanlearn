functions {
  vector step_up(vector g);
  vector step_up_inner(real g, vector b, int k);
  matrix chol_factor_g(vector g, real sigma);
  real ar_model_lpdf(vector y, vector y0, vector b, real sigma);
  vector ar_model_rng(vector y, vector y0, vector b, real sigma);
  vector ar_model_forecast(vector y, vector y0, vector b);
  real ar_initial_values_lpdf(vector y0, real y1, vector g, real sigma);
  vector ar_initial_values_rng(real y1, vector g, real sigma);
  matrix make_toeplitz(vector y, vector y0);
  vector reverse(vector x);

  vector step_up(vector g){
    /*
     * Maps a vector of p reflection coefficients g (|g| < 1) to a
     * stable sequence b of AR coefficients.
     */
    int p = dims(g)[1];  // Model order
    vector[p] b;  // AR Coefficients
    // vector[p] b_cpy;  // Memory

    b[1] = g[1];
    if(p == 1)  // a loop 1:0 is backwards not empty
      return -b;

    for(k in 1:p - 1){
      b[:k + 1] = step_up_inner(g[k + 1], b, k);
    }

    return -b;
  }

  vector step_up_inner(real g, vector b, int k){
    /*
     * Step k (k in 1:p - 1) of the step_up recursion, this is
     * useful for making use of intermediate results.  It
     * consumes the length k sequence b and the k + 1 reflection
     * coefficient g to produce the k + 1 sequence b.  i.e. it
     * uses the model AR(k) and g[k + 1] to produce AR(k + 1).
     */
    vector[k + 1] b_ret;
    for(tau in 1:k)
      b_ret[tau] = b[tau] + g * b[k - tau + 1];
    b_ret[k + 1] = g;
    return b_ret;
  }

  vector inverse_levinson_durbin(vector g, real sigma){
    /* Computes the autocorrelation sequence from the reflection
     * coefficients and the noise level.  This can / should be
     * combined with the step_up recursion to calculate both
     * the autocorrelation and the AR coefficients from (gamma, sigma).
     */
    int p = dims(g)[1];
    vector[p + 1] r_full = rep_vector(0, p + 1);
    vector[p] b;

    b[1] = g[1];

    r_full[1] = sigma^2;
    for(tau in 1:p)
      r_full[1] /= (1 - g[tau]^2);
    r_full[2] = -b[1] * r_full[1];

    for(k in 1:p - 1){
      b[:k + 1] = step_up_inner(g[k + 1], b, k);

      for(tau in 1:k + 1)
        r_full[k + 2] += -b[tau] * r_full[k + 2 - tau];
    }
    return r_full;
  }

  matrix chol_factor_g(vector g, real sigma){
    int p = dims(g)[1];
    vector[p + 1] eps;  // Errors at different modelling orders
    matrix[p + 1, p + 1] E;  // Diag(eps)
    // lower diag matrix of AR coef sequence
    matrix[p + 1, p + 1] B = rep_matrix(0, p + 1, p + 1);

    eps[p + 1] = sigma^2;
    for(tau in 1:p){
      eps[p + 1 - tau] = eps[p + 2 - tau] / (1 - g[p + 1 - tau]^2);
    }
    E = diag_matrix(sqrt(eps));  // The "D" in an LDL^T factor of R

    // This produces an upper triangular matrix
    B = add_diag(B, 1.0);  // ones on the diagonal
    B[1, 2] = g[1];  // k = 1
    for(k in 2:p){
      B[:k, k + 1] = reverse(
        step_up_inner(g[k], reverse(B[:k - 1, k]), k - 1));
    }
    // This is the cholesky factor L of R = symtoep(r).
    return mdivide_left_tri_low(B', E);
    // return B \ E;
  }

  real ar_model_lpdf(vector y, vector y0, vector b, real sigma){
    int T = dims(y)[1];
    vector[T] y_hat = ar_model_forecast(y, y0, b);
    return normal_lpdf(y | y_hat, sigma);
  }

  vector ar_model_rng(vector y, vector y0, vector b, real sigma){
    int T = dims(y)[1];
    vector[T] y_hat = ar_model_forecast(y, y0, b);
    vector[T] y_rng;
    for(t in 1:T)
      y_rng[t] = normal_rng(y_hat[t], sigma);
    return y_rng;
  }

  vector ar_model_forecast(vector y, vector y0, vector b){
    int p = dims(b)[1];
    int T = dims(y)[1];
    vector[T] y_hat;
    vector[p + T] y_full;
    vector[p] b_rev = reverse(b);

    y_full[:p] = y0;
    y_full[p + 1:] = y;

    // A Toeplitz type would be a huge boon to this calculation
    // surprisingly though using make_toeplitz, even if it's kept
    // fixed by non-random y0, doesn't seem to help.
    for(t in 1:T){
      y_hat[t] = dot_product(b_rev, y_full[t:t + p - 1]);
    }
    return y_hat;
  }

  real ar_initial_values_lpdf(vector y0, real y1, vector g, real sigma){
    int p = dims(g)[1];
    matrix[p + 1, p + 1] L = chol_factor_g(g, sigma);
    // (y[1], y0[p], y0[p - 1], ..., y0[1]) is the correct ordering
    // since y0[1] is the farthest back in time and y0[p] is the
    // sample just before y[1].
    return multi_normal_cholesky_lpdf(reverse(append_row(y0, y1)) |
                                      rep_vector(0, p + 1), L);
  }

  vector ar_initial_values_rng(real y1, vector g, real sigma){
    int p = dims(g)[1];
    matrix[p + 1, p + 1] L = chol_factor_g(g, sigma);
    return  multi_normal_cholesky_rng(rep_vector(0, p + 1), L);
  }

  matrix make_toeplitz(vector y, vector y0){
    int p = dims(y0)[1];
    int T = dims(y)[1];    
    vector[p + T] y_full;
    matrix[T, p] Y;

    y_full[:p] = y0;
    y_full[p + 1:] = y;

    for(tau in 1:p)
      Y[:, tau] = y_full[tau:tau + T - 1];
    return Y;
  }

  vector reverse(vector x){
    int p = dims(x)[1];
    vector[p] x_rev;
    for (tau in 1:p)
      x_rev[tau] = x[p - tau + 1];
    return x_rev;
  }
}
