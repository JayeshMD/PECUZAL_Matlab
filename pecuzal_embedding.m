function [Y_tot, tau_vals, ts_vals, LS, epsilons] = pecuzal_embedding(x, varargin)
% PECUZAL_EMBEDDING automated phase space reconstruction method.
%    
%    Y = PECUZAL_EMBEDDING(X) reconstructs fully automatically the 
%    (N-by-M)-matrix Y of phase space vectors from the time series matrix X
%    of size (N0-by-M0) where M0 could be 1 (for time series) or larger for
%    multivariate time series.
%
%    Y = PECUZAL_EMBEDDING(X, TAU) reconstructs the phase space vectors
%    by using vector TAU for which possible delay times the algorithm shall 
%    look (default [0:50]).
%
%    [Y, TAU_VALS, TS_VALS] = PECUZAL_EMBEDDING(...) provides a vector of (different) 
%    time delays TAU_VALS chosen by the algorithm and a vector TS_VALS with the
%    indices between 1 and M0 of chosen time series from matrix X, corresponding to
%    the delays TAU_VALS.
%
%    [Y, TAU_VALS, TS_VALS, L, E] = PECUZAL_EMBEDDING(...) provides a vector L
%    of L-statistic values for the reconstruction in each encountered embedding cycle. 
%    This also includes the L-value of the very last embedding cycle, which does
%    not contribute to the final embedding, due to an increasing L-value. The cell 
%    array E contains all epsilon-mins of the continuity statistic as a function of 
%    TS_VALS for each encountered time series in X.
%
%    ... = PECUZAL_EMBEDDING(..., Name, Value) specifies further optional parameters 
%    for the embedding algorithm using one or more Name, Value pair arguments.
%
%    Optional name-value-arguments:
%      'sample_size' - (default 1) size of the random phase space vector sample the 
%                      algorithm considers for each delay value, in order to compute 
%                      the continuity statistic. This is a float from the intervall
%                      (0 1]. The size of the considered sample is SAMPLE_SIZE*N 
%                      (where N is length of the current phase space trajectory).
%      'theiler'     - (default 1) the temporal correlation window (Theiler window) 
%                      for which no nearest neighbours are considered, because they 
%                      could be direct predecessors or successors of the fiducial point. 
%                      When input X is a multivariate dataset, the Theiler window needs 
%                      to be chosen as the maximum from each of the time series.
%      'alpha'       - (default 0.05) significance level for the continuity statistic.
%      'p'           - (default 0.5) binomial parameter for the continuity statistic.
%      'KNN'         - (default 13) maximal number of points in the delta-neighbourhood. 
%                      For a range of points from [8:KNN] the minimial epsilon-scale 
%                      according to the significance level 'alpha' and binomial parameter
%                      'p' is computed and the minimum of all considered delta-neighborhood
%                      sizes is finally chosen. Must be at least 8.
%      'k'           - (default 3) considered number of nearest neighbors for Uzal's
%                      L-statistic.
%      'Tw_factor'   - (default 4) maximal considered time horizon for obtaining the 
%                      L-statistic as a factor getting multiplied with the Theiler window
%                      TW = TW_FACTOR*THEILER.
%      'max_cycles'  - (default 10) maximum number of embedding cycles the algorithm
%                      performs after which it stops. 
%
%    Example:
%        roe = @(t,x) [-x(2)-x(3); x(1)+0.2*x(2); 0.2+x(3)*(x(1)-5.7)];  % Rossler system
%        [t, x] = ode45(roe, [0 200], [1.; .5; 0.5]); % solve ODE
%        plot3(x(:,1), x(:,2), x(:,3))
%
%        y = pecuzal_embedding(x, 0:100);
%        plot3(y(:,1), y(:,2), y(:,3))
%
%    Further reading:
%    H. K. Kraemer et al., … 2021

% Copyright (c) 2020
% K. Hauke Kraemer, 
% Potsdam Institute for Climate Impact Research, Germany
% http://www.pik-potsdam.de
%
% This program is free software and runs under MIT licence.

%% in- and output check
narginchk(1,21)
nargoutchk(1,5)

%% Assign input

% default values
delay_vals = 0:50;
sample_size = 1.0;
theiler = 1;
alpha = 0.05;
p_val = 0.5;
deltas = 13;
k = 3;
Tw = 4;
max_num_of_cycles = 10;

% required and optional arguments
p = inputParser;

validScalarPosNum1 = @(x) isnumeric(x) && isscalar(x) && (x > 0) && (x <= 1);
validScalarPosNum2 = @(x) isnumeric(x) && isscalar(x) && (x > 0) && rem(x,1)==0;
validDimension = @(x) isnumeric(x) && ismatrix(x);

addRequired(p,'x',validDimension);
addOptional(p,'taus',delay_vals,validDimension);
addParameter(p,'sample_size',sample_size,validScalarPosNum1);
addParameter(p,'theiler',theiler,validScalarPosNum2);
addParameter(p,'alpha',alpha,validScalarPosNum1);
addParameter(p,'p',p_val,validScalarPosNum1);
addParameter(p,'KNN',deltas,validScalarPosNum2);
addParameter(p,'k',k,validScalarPosNum2);
addParameter(p,'Tw_factor',Tw,validScalarPosNum2);
addParameter(p,'max_cycles',max_num_of_cycles,validScalarPosNum2);

% parse input arguments
parse(p,x,varargin{:})

% assign variables with the resulting argument input
x = p.Results.x;
delay_vals = p.Results.taus;
sample_size = p.Results.sample_size;
theiler = p.Results.theiler;
alpha = p.Results.alpha;
p_val = p.Results.p;
deltas = p.Results.KNN;
k = p.Results.k;
Tw = p.Results.Tw_factor * theiler;
max_num_of_cycles = p.Results.max_cycles;

norm = 'euc';

% make the input time series a column vector
if size(x,1)<size(x,2)
    x = x';
end
x_orig = x;

% normalize time series
x = (x-mean(x))./std(x);
xN = size(x,2); % number of time series

%% Start computation
% stop flag for while loop
% (each loop stands for encountering a new embedding dimension)
flag = true;

% compute initial L-value, L_init, for all the time series and take the
% minimum
L_inits = zeros(1,xN);
for i = 1:xN
    L_inits(i) = uzal_cost(x(:,i),theiler,k,Tw,sample_size);
end
L_init = min(L_inits);

% set index-counter for the while loop
cnt = 1;

% preallocation of output
tau_vals = zeros(1,max_num_of_cycles);
ts_vals = zeros(1,max_num_of_cycles);
LS = zeros(1,max_num_of_cycles);
epsilons = cell(1,max_num_of_cycles);

% loop over increasing embedding dimensions until some break criterion will
% tell the loop to stop/break
bar = waitbar(0,'PECUZAL embeds your time series');
while flag
    waitbar(cnt/max_num_of_cycles, bar, sprintf('PECUZAL embeds your time series \nEmbedding cycle %i of maximum %i cycles.', cnt, max_num_of_cycles))
    cnt
    
    % in the first run we need to find the time series to start with, i.e.
    % we have to encounter xN^2 continuity statistics...
    if cnt == 1
        % preallocate storing vectors for some variables in the coming fl
        epsilons_ = cell(1,xN);
        tau_vals__ = zeros(1,xN);
        ts_vals__ = zeros(1,xN);
        LS_ = zeros(1,xN);
        % in the multivariate case we weight each peak with the according
        % L-value
        if xN>1
            COST_ = zeros(1,xN);
        end    
        % Loop over the potential initial time series
        for trial = 1:xN
            % call pecora_embedding_cycle for computing the continuity
            % statistic
            tic, rng(0)
            [epsilons_{trial}, ~, ~, ~,Y_old,~] = ...
                pecora_embedding_cycle(x,tau_vals(1:cnt),trial,...
                                   delay_vals,sample_size,theiler,...
                                   alpha,p_val,deltas,norm);
            toc
%             tic, rng(0)
%             [epsilons_2{trial}, ~, ~, ~,Y_old2,~] = ...
%                 pecora_embedding_cycle2(x,tau_vals(1:cnt),trial,...
%                                    delay_vals,sample_size,theiler,...
%                                    alpha,p_val,deltas,norm);
%             toc
            % preallocate storing vector for the possible peaks of the 
            % continuity statistic
            tau_use = ones(1,xN); 
            Ls = zeros(1,xN);
            if xN>1
                cost = zeros(1,xN);
            end
            % loop over the statistics for each time series
            for ts = 1:xN
                % extract the corresponding continuity statistic
                epsilon_min_avrg = epsilons_{trial};         
                epsilon_min_avrg = epsilon_min_avrg(:,ts);
                % add 0 to account for lag 0 being also a peak
                epsilon_min_avrg = [0; epsilon_min_avrg]; 
                % Look for the local maxima:
                [pks,locs] = findpeaks(epsilon_min_avrg,'MinPeakDistance',2);
                if isempty(pks)
                    tau_use(ts)= NaN;
                    Ls(ts) = NaN;
                    continue
                else                 
                    tau_use_ = zeros(1,length(pks));
                    Ls_ = zeros(1,length(pks));
                    if xN>1
                        cost_ = zeros(1,length(pks));
                    end
                    % loop over the local maxima
                    for i = 1:length(pks)
                        % assign tau value to this peak; minus 1, because 
                        % one zero padding 
                        tau_use_(i) = delay_vals(locs(i)-1);                      
                        % compute L-statistic
                        Y_new = embed2(Y_old,x(:,ts),tau_use_(i));
                        Ls_(i) = uzal_cost(Y_new,theiler,k,Tw,sample_size);
                        if xN>1
                            cost_(i) = Ls_(i)*pks(i);
                        end
                    end    
                    % pick the peak, which goes along with the least L/cost
                    if xN>1
                        [~, order] = sort(cost_);
                    else
                        [~, order] = sort(Ls_);
                    end
                    tau_use_ = tau_use_(order);
                    tau_use(ts) = tau_use_(1);
                    Ls(ts) = Ls_(order(1));
                    if xN>1
                        cost(ts) = cost_(order(1));
                    end
                end              
            end  
              
            if xN>1               
                % Again, take the combination of time series, which yield a
                % minimum cost (=peak-height*L)
                [~,order] = sort(cost);
                tau_use = tau_use(order);             
                tau_vals__(trial) = tau_use(1);
                ts_vals__(trial) = order(1);
                LS_(trial) = Ls(order(1));
                COST_(trial) = cost(order(1));
            else
                tau_vals__(trial) = tau_use(1);
                ts_vals__(trial) = 1;
                LS_(trial) = Ls;
            end                 
        end
        % now compare the results for all different initial time series and
        % store the values. Sort by the smallest amount of L / cost
        if xN>1
            [~,ind] = sort(COST_);
        else
            [~,ind] = sort(LS_);
        end
        LS(1) = LS_(ind(1));
        ts_vals(1) = ind(1);
        ts_vals(2) = ts_vals__(ind(1)); 
        tau_vals(2) = tau_vals__(ind(1));
        epsilons{1} = epsilons_{ind(1)};
        % check break criteria
        if break_criteria(tau_vals, LS, max_num_of_cycles, cnt, L_init)
            tau_vals = tau_vals(1:cnt);
            ts_vals = ts_vals(1:cnt);
            LS = LS(1:cnt);
            epsilons = epsilons(1:cnt);
            flag = false;
        end
    
    % in all embedding cycles, but the first one, encounter "only" xN 
    % continuity statistics
    else
        % call pecora_embed_ts for computing the continuity statistic
        [epsilons{cnt}, ~, ~, ~, Y_old, ~] = pecora_embedding_cycle(x,...
                  tau_vals(1:cnt),ts_vals(1:cnt),delay_vals,sample_size,...
                           theiler,alpha,p_val,deltas,norm);          
        % preallocate storing vector for the possible peaks of the continuity
        % statistic
        tau_use = ones(1,xN);
        Ls = zeros(1,xN);
        % loop over the statistics for each time series
        for ts = 1:xN
            % extract corresponding continuity statistic
            epsilon_min_avrg = epsilons{cnt};
            epsilon_min_avrg = epsilon_min_avrg(:,ts);
            epsilon_min_avrg = [0; epsilon_min_avrg];
            % find local maxima in the continuity statistic
            [pks,locs] = findpeaks(epsilon_min_avrg,'MinPeakDistance',2);
            if isempty(pks)
                tau_use(ts)= NaN;
                Ls(ts)=NaN;
                continue
            else
                % preallocate some variables
                tau_use_ = zeros(1,length(pks));
                Ls_ = zeros(1,length(pks)); 
                for i = 1:length(pks)
                    % now assign the tau value to this peak, minus 1, 
                    % because one zero padding
                    tau_use_(i) = delay_vals(locs(i)-1);  
                    % compute L-statistic
                    Y_new = embed2(Y_old,x(:,ts),tau_use_(i));
                    Ls_(i) = uzal_cost(Y_new,theiler,k,Tw,sample_size);
                    
                end
                % pick the peak, which goes along with minimum L
                [~, order] = sort(Ls_);
                tau_use_ = tau_use_(order);

                tau_use(ts) = tau_use_(1);
                Ls(ts) = Ls_(order(1));

            end
        end
        % Now pick the peak of all the "valid" ones from each time series
        if xN>1  
            % again, minimize the L-statistic
            [~,order] = sort(Ls);
            tau_use = tau_use(:,order);             
            tau_vals(cnt+1) = tau_use(1);
            ts_vals(cnt+1) = order(1);
            LS(cnt) = Ls(order(1));
        else
            tau_vals(cnt+1) = tau_use(1);
            ts_vals(cnt+1) = 1;
            LS(cnt) = Ls;
        end
        % check break criteria
        if break_criteria(tau_vals, LS, max_num_of_cycles, cnt, L_init)
            tau_vals = tau_vals(1:cnt);
            ts_vals = ts_vals(1:cnt);
            LS = LS(1:cnt);
            epsilons = epsilons(1:cnt);
            flag = false;
        end
    end
    % increase dimension index counter  
    cnt = cnt + 1;   
end
close(bar)

% final reconstruction
for m = 1:length(tau_vals)
    if m == 1
        Y_tot = embed(x_orig(:,ts_vals(m)),m,tau_vals(m));
    else
        Y_tot = embed2(Y_tot,x_orig(:,ts_vals(m)),tau_vals(m));
    end
end

end

