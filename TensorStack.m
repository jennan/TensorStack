% TensorStack - CLASS Create a seamless stack of tensors
%
% Usage: tsTensor = TensorStack(nCatDim, tfTensor1 <, tfTensor2, tfTensor3, ...>)
%
% 'nCatDim' is a dimension along which to contacentate several tensors.
% 'tfTensor1', ..., 'tfTensorN' must all have identical sizes, except for
% along the dimensions 'nCatDim'.
%
% 'tsTensor' will be a TensorStack object, which appears like a normal
% matlab tensor. It can be referenced using normal matlab indexing, with
% some restrictions. All-colon referencing is unrestricted. However, when
% any subscript contains a non-colon reference, then the dimensions up
% until and including the concatenated stack dimension 'nCatDim' must be
% referenced individually. Subsequent dimensions may be wrapped up using
% partial linear referencing.
%
% For example:
%
% >> tsTensor = TensorStack(1, ones(3, 3, 3), ones(3, 3, 3))
%
% tsTensor = 
%    6x3x3 TensorStack object.
%
% >> size(tsTensor(:))
%
% ans = [54 1]
%
% >> size(tsTensor(:, :))
%
% ans = [3 18]
%
% >> tsTensor(12)
%
% Error using TensorStack/my_subsref (line 178)
% *** TensorStack: Only limited referencing styles are supported. The concatenated stack dimension [2] must be referenced independently.
%
% >> size(tsTensor(2, :))
%
% ans = [1 9]
%
% >> tsTensor(1, 7)
%
% ans = 1

% Author: Dylan Muir <dylan.muir@unibas.ch>
% Created: July 2015

classdef TensorStack
   properties (SetAccess = private, GetAccess = private)
      nStackDim;        % - Dimension along which concatenation has taken place
      ctTensors;        % - Cell array of sub-tensors
      cvnTensorSizes;   % - Cell array containing buffered sizes
      strDataClass;     % - Buffered data class
   end
   
   methods
      %% TensorStack - Constructor
      function oStack = TensorStack(varargin)
         % -- Check arguments
         if (nargin < 2)
            help TensorStack;
            error('TensorStack:Usage', ...
                  '*** TensorStack: Incorrect usage.');
         end
         
         % - Buffer tensor sizes
         oStack.nStackDim = varargin{1};
         oStack.cvnTensorSizes = cellfun(@size, varargin(2:end), 'UniformOutput', false);

         % - Check dimension argument
         if (~isnumeric(oStack.nStackDim) || (oStack.nStackDim < 1))
            error('TensorStack:Arguments', ...
                  '*** TensorStack: Stacking dimension must be a number > 1.');
         end
         
         % - Check that all tensors have the same size (apart from stack dimension)
         cvnCheckDims = oStack.cvnTensorSizes;
         for (nTensor = 1:numel(cvnCheckDims))
            cvnCheckDims{nTensor}(oStack.nStackDim) = 0;
         end
         
         if (~all(cellfun(@(c)isequal(c, cvnCheckDims{1}), cvnCheckDims(2:end))))
            error('TensorStack:Arguments', ...
                  '*** TensorStack: All tensors must be of the same dimensions, apart from stacking dimension.');
         end
         
         % - Check that all tensors have the same data class
         oStack.strDataClass = class(varargin{2}(1));
         if (~all(cellfun(@(c)isequal(class(c(1)), oStack.strDataClass), varargin(2:end))))
            error('TensorStack:Arguments', ...
                  '*** TensorStack: All tensors must be of the same numeric class.');
         end
         
         % -- Store sub-tensors
         oStack.ctTensors = varargin(2:end);
      end
      
      
      %% -- Overloaded subsref, subsasgn
      function [varargout] = subsref(oStack, S)
         % - More than one return argument means cell or dot referencing was
         % used
         if (nargout > 1)
            error('TensorStack:InvalidReferencing', ...
               '*** TensorStack: ''{}'' and ''.'' referencing methods are not supported by TensorStack objects.');
         end
         
         % - Check reference type
         switch (S(1).type)
            case {'.', '{}'}
               % - Unsupported referencing
               error('TensorStack:InvalidReferencing', ...
               '*** TensorStack: ''{}'' and ''.'' referencing methods are not supported by TensorStack objects.');
               
            case {'()'}
               % - Call the internal subsref function
               [varargout{1}] = my_subsref(oStack, S);

            otherwise
               % - Unknown referencing type
               error('TensorStack:UnknownReferenceType', ...
                  '*** TensorStack: An unknown referencing method was used.');
         end
      end
      
      % subsasgn - Overloaded subsasgn
      function varargout = subsasgn(~, ~, ~)
         error('TensorStack:NotSupported', ...
               '*** TensorStack: Assignment is not supported.');
      end
      
      % my_subsref - Standard array referencing
      function [tfData] = my_subsref(oStack, S)
         % - Test for valid subscripts
         cellfun(@isvalidsubscript, S.subs);
         
         % - Get stack information
         nNumDims = numel(S.subs);
         vnReferencedTensorSize = size(oStack);
         nNumTotalDims = numel(vnReferencedTensorSize);
         
         % - Check dimensionality and trailing dimensions
         if (nNumDims > nNumTotalDims)
            % - Check trailing dimensions
            if (~all(cellfun(@(c)isequal(c, 1), S.subs(nNumTotalDims+1:end))))
               error('TensorStack:badsubscript', ...
                  '*** TensorStack: Index exceds matrix dimensions.');
            end
            
            % - Trim trailing dimensions
            S.subs = S.subs(1:nNumTotalDims);
            nNumDims = nNumTotalDims;
         end
         
         % - Correct for wrapped-up tensor dimensions
         vnReferencedTensorSize(nNumDims) = prod(vnReferencedTensorSize(nNumDims:end));
         vnReferencedTensorSize = vnReferencedTensorSize(1:nNumDims);
         
         % - Catch "all colon" entire stack referencing
         vbIsColon = cellfun(@iscolon, S.subs);
         if (all(vbIsColon))
            % - Allocate return tensor, using buffered data class
            tfData = zeros(size(oStack), oStack.strDataClass);
            
            % - Catch linear referencing
            if (nNumDims == 1)
               vnReferencedTensorSize(2) = 1;
            end
            
            % - Loop over sub-tensors, referencing them in turn
            vnStackLengths = cellfun(@(c)c(oStack.nStackDim), oStack.cvnTensorSizes);
            vnStackStarts = [0 cumsum(vnStackLengths)];
            vnStackEnds = vnStackStarts(2:end);
            vnStackStarts = vnStackStarts(1:end-1)+1;
         
            cBaseSubs = repmat({':'}, 1, ndims(oStack));
            
            for (nSubTensor = 1:numel(oStack.ctTensors))
               % - Map tensor and data subscripts
               cDataSubs = cBaseSubs;
               cDataSubs{oStack.nStackDim} = vnStackStarts(nSubTensor):vnStackEnds(nSubTensor);
               
               % - Access sub-tensor data
               tfData(cDataSubs{:}) = oStack.ctTensors{nSubTensor}(cBaseSubs{:});
            end
            
            % - Reshape and return data
            tfData = reshape(tfData, vnReferencedTensorSize);
            return;
         end
         
         if (nNumDims < nNumTotalDims)
            % - Only possible if the concatenation dimension preceeds the wrapped-up dimensions
            if (nNumDims <= oStack.nStackDim)
               error('TensorStack:badsubscript', ...
                     '*** TensorStack: Only limited referencing styles are supported. The concatenated stack dimension [%d] must be referenced independently.', ...
                     oStack.nStackDim);
            end
         end

         % - Convert colon referencing
         for (nRefDim = find(vbIsColon))
            S.subs{nRefDim} = 1:vnReferencedTensorSize(nRefDim);
         end
         
         % - Check stack references
         if (any(cellfun(@(s)min(s(:)), S.subs) < 1) || any(cellfun(@(s)max(s(:)), S.subs) > vnReferencedTensorSize))
            error('TensorStack:badsubscript', ...
                  'Index exceeds matrix dimensions.');
         end
         
         % - Allocate return tensor, using buffered data class
         vnDataSize = cellfun(@nnz, S.subs);
         tfData = zeros(vnDataSize, oStack.strDataClass);
         
         % - Loop over sub-tensors, referencing them in turn
         vnStackLengths = cellfun(@(c)c(oStack.nStackDim), oStack.cvnTensorSizes);
         vnStackStarts = [0 cumsum(vnStackLengths)];
         vnStackEnds = vnStackStarts(2:end);
         vnStackStarts = vnStackStarts(1:end-1)+1;
         
         cBaseDataSubs = cellfun(@substodatasubs, S.subs, 'UniformOutput', false);
         
         for (nSubTensor = 1:numel(oStack.ctTensors))
            % - Work out which indices are within this tensor
            vbThisTensor = (S.subs{oStack.nStackDim} >= vnStackStarts(nSubTensor)) & ...
               (S.subs{oStack.nStackDim} <= vnStackEnds(nSubTensor));
            
            if any(vbThisTensor)
               % - Map tensor and data subscripts
               cTensorSubs = S.subs;
               cTensorSubs{oStack.nStackDim} = S.subs{oStack.nStackDim}(vbThisTensor) - vnStackStarts(nSubTensor)+1;
               cDataSubs = cBaseDataSubs;
               cDataSubs{oStack.nStackDim} = vbThisTensor;
               
               % - Access sub-tensor data
               tfData(cDataSubs{:}) = oStack.ctTensors{nSubTensor}(cTensorSubs{:});
            end
         end
      end
      
      
      %% -- Overloaded size, numel, end, etc
      % size - METHOD Overloaded size
      function varargout = size(oStack, vnDimensions)
         % - Get tensor stack size
         vnSize = oStack.cvnTensorSizes{1};
         vnStackLengths = cellfun(@(c)c(oStack.nStackDim), oStack.cvnTensorSizes);
         vnSize(oStack.nStackDim) = sum(vnStackLengths);
         
         % - Return specific dimension(s)
         if (exist('vnDimensions', 'var'))
            if (~isnumeric(vnDimensions) || ~all(isreal(vnDimensions)))
               error('TensorStack:dimensionMustBePositiveInteger', ...
                  '*** TensorStack: Dimensions argument must be a positive integer within indexing range.');
            end
            
            % - Return the specified dimension(s)
            vnSize = vnSize(vnDimensions);
         end
         
         % - Handle differing number of size dimensions and number of output
         % arguments
         nNumArgout = max(1, nargout);
         
         if (nNumArgout == 1)
            % - Single return argument -- return entire size vector
            varargout{1} = vnSize;
            
         elseif (nNumArgout <= numel(vnSize))
            % - Several return arguments -- return single size vector elements,
            % with the remaining elements grouped in the last value
            varargout(1:nNumArgout-1) = num2cell(vnSize(1:nNumArgout-1));
            varargout{nNumArgout} = prod(vnSize(nNumArgout:end));
            
         else
            % - Output all size elements
            varargout(1:numel(vnSize)) = num2cell(vnSize);

            % - Deal out trailing dimensions as '1'
            varargout(numel(vnSize)+1:nNumArgout) = {1};
         end
      end
      
      % numel - METHOD Overloaded numel
      function [nNumElem] = numel(oStack, varargin)
         % - If varargin contains anything, a cell reference "{}" was attempted
         if (~isempty(varargin))
            error('TensorStack:cellRefFromNonCell', ...
               '*** TensorStack: Cell contents reference from non-cell obejct.');
         end
         
         % - Return the total number of elements in the tensor
         nNumElem = prod(size(oStack)); %#ok<PSIZE>
      end
      
      % ndims - METHOD Overloaded ndims
      function [nNumDims] = ndims(oStack)
         nNumDims = numel(size(oStack));
      end
      
      % end - METHOD Overloaded end
      function ind = end(obj,k,n)
         szd = size(obj);
         if k < n
            ind = szd(k);
         else
            ind = prod(szd(k:end));
         end
      end
      
      % permute - METHOD Overloaded permute
      function varargout = permute(varargin) %#ok<*STOUT>
         error('TensorStack:NotSupported', ...
               '*** TensorStack: ''permute'' is not supported.');
      end
      
      % permute - METHOD Overloaded ipermute
      function varargout = ipermute(varargin)
         error('TensorStack:NotSupported', ...
               '*** TensorStack: ''ipermute'' is not supported.');
      end
      
      % permute - METHOD Overloaded transpose
      function varargout = transpose(varargin)
         error('TensorStack:NotSupported', ...
               '*** TensorStack: ''transpose'' is not supported.');
      end
      
      % permute - METHOD Overloaded ctranspose
      function varargout = ctranspose(varargin)
         error('TensorStack:NotSupported', ...
               '*** TensorStack: ''ctranspose'' is not supported.');
      end
      
      %% -- Overloaded disp
      function disp(oStack)
         strSize = strtrim(sprintf('%dx', size(oStack)));
         strSize = strSize(1:end-1);

         disp(sprintf('   %s <a href="matlab:help TensorStack">TensorStack</a> object. <a href="matlab:methods(''TensorStack'')">Methods</a> <a href="matlab:properties(''TensorStack'')">Properties</a>', strSize)); %#ok<DSPS>
         fprintf(1, '\n');
      end
      
      %% -- Overloaded test functions
      function bIsNumeric = isnumeric(oStack)
         bIsNumeric = isnumeric(oStack.ctTensors{1});
      end
      
      function bIsReal = isreal(oStack)
         bIsReal = isreal(oStack.ctTensors{1});
      end
      
      function bIsLogical = islogical(oStack)
         bIsLogical = islogical(oStack.ctTensors{1});
      end
      
      function bIsScalar = isscalar(oStack)
         bIsScalar = numel(oStack) == 1;
      end
      
      function bIsMatrix = ismatrix(oStack)
         bIsMatrix = ~isscalar(oStack);
      end
      
      function bIsChar = ischar(oStack)
         bIsChar = ischar(oStack.ctTensors{1});
      end
      
      function bIsNan = isnan(oStack) %#ok<MANU>
         bIsNan = false;
      end
   end
   
   
end

%% -- Helper functions

% iscolon - FUNCTION Test whether a reference is equal to ':'
function bIsColon = iscolon(ref)
   bIsColon = ischar(ref) && isequal(ref, ':');
end

% isvalidsubscript - FUNCTION Test whether a vector contains valid entries
% for subscript referencing
function isvalidsubscript(oRefs)
   try
      % - Test for colon
      if (iscolon(oRefs))
         return;
      end
      
      if (islogical(oRefs))
         % - Test for logical indexing
         validateattributes(oRefs, {'logical'}, {'binary'});
         
      else
         % - Test for normal indexing
         validateattributes(oRefs, {'single', 'double'}, {'integer', 'real', 'positive'});
      end
      
   catch
      error('MappedTensor:badsubscript', ...
            '*** MappedTensor: Subscript indices must either be real positive integers or logicals.');
   end
end

function vDataSubs = substodatasubs(vSubs)
   if islogical(vSubs)
      vDataSubs = 1:nnz(vSubs);
   else
      vDataSubs = 1:numel(vSubs);
   end
end
