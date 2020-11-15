function [distances,comp_dist] = all_distances(varargin)
% all_distances computes all componentwise distances from one point 
% (a vector) to all other given points, but not all pairwise distances 
% between all points.
% This function is meant to determine the neighbourhood of a certain point
% without computing the whole distances matrix (as being done by the 
% pdist()-function)
%
% [distances, comp_dist] = all_distances(fid_point,Y,norm) computes all 
% distances, based from the input vector 'fid_point' to all other 
% points/vectors stored in the input 'Y' and stores it in output 
% 'distances'. The componentwise distances are stored in output 'comp_dist'
%
%
% K.H.Kraemer, Mar 2020

fid_point = varargin{1};
Y = varargin{2};


methLib={'euc','max'}; % the possible norms
try
    meth = varargin{3};
    if ~isa(meth,'char') || ~ismember(meth,methLib)
       warning(['Specified norm should be one of the following possible values:',...
           10,sprintf('''%s'' ',methLib{:})])
    end
catch
    meth = 'euc';
end


% compute distances to all other points
% YY = zeros(size(Y));
% for p = 1:size(YY,1)
%     YY(p,:) = fid_point;
% end
YY = repmat(fid_point,size(Y,1),1);
if strcmp(meth,'euc')
    distances = sqrt(sum((YY - Y) .^ 2, 2));
elseif strcmp(meth,'max')
    distances = max(abs(YY - Y),[],2);
end

if nargout > 1
    comp_dist = abs(YY - Y);
end

end

