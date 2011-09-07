function[vz,coeffs,w,mom] = greens_lift(nodes, v, z, grid, d, ht)
% greens_lift -- Evaluates the WP greens lift of velocity fields
%
% [vz,coeffs,w,mom] = greens_lift(nodes, v, z, grid, [[d=0, ht=[] ]])
%
%     If nodes and v are vectors of the same size, this function computes the WP
%     greens lift coefficients coeffs and w that correspond to the
%     velocity field evaluations (nodes, v). The greens lift is evaluated
%     at the locations z, and fz is of the same size as z. The d'th derivative
%     is evaluated, and so far this function is valid for d=1,2. Ndof =
%     length(coeffs), 3 = length(w), and Nv = size(nodes,1). This also returns
%     the momenta 'mom', which is a length-Nv vector such that mom'*v returns
%     the norm.
%
%     The scalar N denotes the size of the space used to approximate the lift:
%     the functions G(x - grid(1)), G(x - grid(2)), ..., G(x - grid(N)), where N
%     = length(grid). This finds the minimum-norm least-squares solution.
%     Least-squares is measured in the WP Gram matrix on 'nodes'.
%
%     If nodes and v are arrays of the same size, then the input z must be an
%     array with the same number of columns. Let [N,M] = size(nodes). Then this
%     function assumes that there are M collections of length-Nv nodes and data:
%     (nodes(:,m), data(:,m)). The horizontal lift of all of these is computed
%     by assigning equal weight to each lift and finding the kernel coefficients
%     w that simultaneously minimize the sum of WP norms of the lifts. Then
%     [N,M] = size(m) and 3 = length(w). Then for m = 1, 2, ..., M, the m'th
%     horizontal lift is evaluated at z(:,m) and the result is stored in
%     vz(:,m). Again, the d'th derivative is computed.
%
%     The input z can be empty in which case vz is empty and m and w contain the
%     coefficients.
%
%     The input 'ht' determines weights to be put on each ensemble member.
%     Therefore, length(ht)==M.
%
%     The workhorse for this routine is the gsvd.

persistent kernel_basis greens_matrix greens_function
if isempty(kernel_basis)
  from shapelab.wp import kernel_basis greens_function greens_matrix
end

[Nv,M] = size(nodes);

% Input validation
if nargin < 6
  ht = ones([M 1]);
  if nargin < 5
    d = 0;
    if nargin < 4
      grid = nodes;
      if nargin < 3
        z = [];
      end
    end
  end
end

if any([Nv,M] ~= size(v));
  error('Inputs ''nodes'' and ''v'' must be of the same size');
end
if (M ~= size(z,2)) & (size(z,2) > 0)
  error('Input ''z'' must have the same number of columns as ''nodes''');
end

% The number of dof in the basis set is actually 2*(N-1)
Ndof = length(grid(:));
NMdof = M*Ndof;

% These can be huge matrices:
% Possible TODO: sparse matrix with svds --> gsvds?
G = zeros([Nv*M NMdof+3]);
L = zeros([NMdof NMdof+3]);

gram = greens_matrix(grid(:));
temp = chol(gram);
gridy = repmat(grid(:).', [Nv 1]);

for m = 1:M
  i1 = 1 + (m-1)*Nv;
  i2 = m*Nv;
  i3 = 1 + (m-1)*Ndof;
  i4 = m*Ndof;
  G(i1:i2,i3:i4) = greens_function(repmat(nodes(:,m), [1 Ndof]) - gridy);
  L(i3:i4,i3:i4) = temp*sqrt(ht(m));

  G(i1:i2,end-2:end) = kernel_basis(nodes(:,m));

  if (Ndof + 3 < Nv)  % compute least-squares solution
    blah = chol(greens_matrix(nodes(:,m)));
    G(i1:i2,:) = blah*G(i1:i2,:);
    v(:,m) = blah*v(:,m);
  end
end

[U,V,X,C,S] = gsvd(G, L);

% The old-school way
%pinvC = spdiags(1./diag(C,3), -3, N*M+3, N*M);
%H = inv(X')*pinvC*U';
%mw = H*v(:);

% All the cool kids are doing it this equivalent way;
if (Ndof + 3) >= Nv;
  diagC = 1./diag(C,NMdof-Nv*M+3);
  diagC(isinf(diagC)) = 0;
  mw = X'\[zeros([NMdof-Nv*M+3 1]); diagC.*(U'*v(:))];

  mom = mw;
  for m = 1:M
    i1 = 1 + (m-1)*Ndof;
    i2 = m*Ndof;
    mom(i1:i2) = gram*ht(m)*mom(i1:i2);
  end
  mom(NMdof+1:end) = 0;
  %mom(1:NMdof) = (diag(L).^2).*mom(1:NMdof); mom(NMdof+1:end) = 0;
  mom = X\mom;
  mom = U*(diagC.*mom(NMdof-Nv*M+3+1:end));
else
  diagC = 1./diag(C);
  temp = U'*v(:);
  mw = X'\[diagC.*temp(1:(NMdof+3))];

  mom = mw;
  for m = 1:M
    i1 = 1 + (m-1)*Ndof;
    i2 = m*Ndof;
    mom(i1:i2) = gram*ht(m)*mom(i1:i2);
  end
  mom(NMdof+1:end) = 0;
  %mom(1:NMdof) = (diag(L).^2).*mom(1:NMdof); mom(NMdof+1:end) = 0;
  mom = X\mom;
  mom = U*(diagC.*mom(NMdof-Nv*M+3+1:end));
end

coeffs = reshape(mw(1:NMdof), [Ndof M]);
mom = reshape(mom, [Nv M]);
w = mw(NMdof+1:end);

% Now evaluate the lift
gridy = repmat(grid(:).', [size(z,1) 1]);
if isempty(z)
  vz = [];
else
  vz = zeros(size(z));
  for m = 1:M
    vz(:,m) = greens_function(repmat(z(:,m), [1 Ndof]) - gridy)*coeffs(:,m) + ...
              kernel_basis(z(:,m), d)*w;
    %vz(:,m) = trigonometric_matrix(z(:,m), N, d)*coeffs(:,m) + ...
    %          kernel_basis(z(:,m), d)*w;
  end
end
