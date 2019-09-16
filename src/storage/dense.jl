export Dense

contract_t = 0.0

struct Dense{T} <: TensorStorage
  data::Vector{T}
  Dense{T}(data::Vector) where {T} = new{T}(convert(Vector{T},data))
  Dense{T}(size::Integer) where {T} = new{T}(Vector{T}(undef,size))
  Dense{T}(x::Number,size::Integer) where {T} = new{T}(fill(convert(T,x),size))
  Dense{T}() where {T} = new{T}(Vector{T}())
end

data(D::Dense) = D.data
length(D::Dense) = length(data(D))
eltype(D::Dense) = eltype(data(D))
Base.getindex(D::Dense,i::Integer) = getindex(data(D),i)
Base.setindex!(D::Dense,x,i::Integer) = setindex!(data(D),x,i)
#TODO: this should do proper promotions of the storage data
#e.g. ComplexF64*Dense{Float64} -> Dense{ComplexF64}
*(D::Dense{T},x::S) where {T,S<:Number} = Dense{promote_type(T,S)}(x*data(D))
*(x::Number,D::Dense) = D*x

Base.promote_type(::Type{Dense{T1}},::Type{Dense{T2}}) where {T1,T2} = Dense{promote_type(T1,T2)}

convert(::Type{Dense{T}},D::Dense) where {T} = Dense{T}(data(D))

storage_convert(::Type{Dense{T}},D::Dense,is::IndexSet) where {T} = convert(Dense{T},D)

# convert to complex
storage_complex(D::Dense{T}) where {T} = Dense{complex(T)}(complex(data(D)))

copy(D::Dense{T}) where {T} = Dense{T}(copy(data(D)))

function storage_outer(D1::Dense{T},is1::IndexSet,D2::Dense{S},is2::IndexSet) where {T, S <:Number}
  return Dense{promote_type(T,S)}(vec(data(D1)*transpose(data(D2)))),IndexSet(is1,is2)
end

storage_convert(::Type{Array},D::Dense,is::IndexSet) = reshape(data(D),dims(is))

function storage_convert(::Type{Array},
                         D::Dense,
                         ois::IndexSet,
                         nis::IndexSet)
  P = calculate_permutation(nis,ois)
  A = reshape(data(D),dims(ois))
  return permutedims(A,P)
end

storage_fill!(D::Dense,x::Number) = fill!(data(D),x)

function storage_getindex(Tstore::Dense{T},
                          Tis::IndexSet,
                          vals::Union{Int, AbstractVector{Int}}...) where {T}
  return getindex(reshape(data(Tstore),dims(Tis)),vals...)
end

function storage_setindex!(Tstore::Dense,
                           Tis::IndexSet,
                           x::Union{<:Number, AbstractArray{<:Number}},
                           vals::Union{Int, AbstractVector{Int}}...)
  return setindex!(reshape(data(Tstore),dims(Tis)),x,vals...)
end

# For use in _add!
using Base.Cartesian: @nexprs,
                      @ntuple,
                      @nloops

#
# A generalized permutedims!(P,B,perm) that also allows
# a function to be applied elementwise (defaults to addition of
# the elements of P and the permuted elements of B)
#
# Based off of the permutedims! implementation in Julia's base:
# https://github.com/JuliaLang/julia/blob/91151ab871c7e7d6689d1cfa793c12062d37d6b6/base/multidimensional.jl#L1355
#
@generated function _add!(P::Array{T,N},
                          B::Array{S,N},
                          perm,
                          f = (x,y)->x+y) where {T,S,N}
  quote
    Base.checkdims_perm(P, B, perm)

    #calculates all the strides
    native_strides = Base.size_to_strides(1, size(B)...)
    strides_1 = 0
    @nexprs $N d->(strides_{d+1} = native_strides[perm[d]])

    #Creates offset, because indexing starts at 1
    offset = 1 - sum(@ntuple $N d->strides_{d+1})

    ind = 1
    @nexprs 1 d->(counts_{$N+1} = strides_{$N+1}) # a trick to set counts_($N+1)
    @nloops($N, i, P,
            d->(counts_d = strides_d), # PRE
            d->(counts_{d+1} += strides_{d+1}), # POST
            begin # BODY
                sumc = sum(@ntuple $N d->counts_{d+1})
                @inbounds P[ind] = f(P[ind],B[sumc+offset])
                ind += 1
            end)

    return P
  end
end

function _add!(Bstore::Dense,
               Bis::IndexSet,
               Astore::Dense,
               Ais::IndexSet,
               x::Number = 1)
  p = calculate_permutation(Bis,Ais)
  Adata = data(Astore)
  Bdata = data(Bstore)
  if is_trivial_permutation(p)
    if x == 1
      Bdata .+= Adata
    else
      Bdata .= Bdata .+ x .* Adata
    end
  else
    reshapeBdata = reshape(Bdata,dims(Bis))
    reshapeAdata = reshape(Adata,dims(Ais))
    if x == 1
      _add!(reshapeBdata,reshapeAdata,p)
    else
      _add!(reshapeBdata,reshapeAdata,p,(a,b)->a+x*b)
    end
  end
end

function storage_copyto!(Bstore::Dense,
                         Bis::IndexSet,
                         Astore::Dense,
                         Ais::IndexSet,
                         x::Number = 1)
  p = calculate_permutation(Bis,Ais)
  Adata = data(Astore)
  Bdata = data(Bstore)
  if is_trivial_permutation(p)
    if x == 1
      Bdata .= Adata
    else
      Bdata .= x .* Adata
    end
  else
    reshapeBdata = reshape(Bdata,dims(Bis))
    reshapeAdata = reshape(Adata,dims(Ais))
    if x == 1
      _add!(reshapeBdata,reshapeAdata,p,(a,b)->b)
    else
      _add!(reshapeBdata,reshapeAdata,p,(a,b)->x*b)
    end
  end
end

function storage_mult!(Astore::Dense,
                       x::Number)
  Adata = data(Astore)
  rmul!(Adata, x)
end

function storage_mult(Astore::Dense,
                      x::Number)
  Bstore = copy(Astore)
  storage_mult!(Bstore, x)
  return Bstore
end

# For Real storage and complex scalar, promotion
# of the storage is needed
function storage_mult(Astore::Dense{T},
                      x::S) where {T<:Real,S<:Complex}
  Bstore = convert(Dense{promote_type(S,T)},Astore)
  storage_mult!(Bstore, x)
  return Bstore
end


# TODO: make this a special version of storage_add!()
# Make sure the permutation is optimized
function storage_permute!(Bstore::Dense, Bis::IndexSet,
                          Astore::Dense, Ais::IndexSet)
  p = calculate_permutation(Bis,Ais)
  Adata = data(Astore)
  Bdata = data(Bstore)
  if is_trivial_permutation(p)
    Bdata .= Adata
  else
    reshapeBdata = reshape(Bdata,dims(Bis))
    permutedims!(reshapeBdata,reshape(Adata,dims(Ais)),p)
  end
end

function storage_dag(Astore::Dense,Ais::IndexSet)
  return dag(Ais),storage_conj(Astore)
end

function storage_scalar(D::Dense)
  length(D)==1 && return D[1]
  throw(ErrorException("Cannot convert Dense -> Number for length of data greater than 1"))
end

function _contract(Cinds::IndexSet, Clabels::Vector{Int},
                   Astore::Dense{SA}, Ainds::IndexSet, Alabels::Vector{Int},
                   Bstore::Dense{SB}, Binds::IndexSet, Blabels::Vector{Int}) where {SA<:Number,SB<:Number}
  SC = promote_type(SA,SB)

  # Convert the arrays to a common type
  # since we will call BLAS
  Astore = convert(Dense{SC},Astore)
  Bstore = convert(Dense{SC},Bstore)

  Adims = dims(Ainds)
  Bdims = dims(Binds)
  Cdims = dims(Cinds)

  # Create storage for output tensor
  Cstore = Dense{SC}(prod(Cdims))

  Adata = reshape(data(Astore),Adims)
  Bdata = reshape(data(Bstore),Bdims)
  Cdata = reshape(data(Cstore),Cdims)

  if(length(Alabels)==0)
    contract_scalar!(Cdata,Clabels,Bdata,Blabels,Adata[1])
  elseif(length(Blabels)==0)
    contract_scalar!(Cdata,Clabels,Adata,Alabels,Bdata[1])
  else
    props = CProps(Alabels,Blabels,Clabels)
    compute!(props,Adata,Bdata,Cdata)
    _contract_dense_dense!(Cdata,props,Adata,Bdata)
  end

  return Cstore
end

function storage_svd(Astore::Dense{T},
                     Lis::IndexSet,
                     Ris::IndexSet;
                     kwargs...) where {T}
  maxdim::Int = get(kwargs,:maxdim,min(dim(Lis),dim(Ris)))
  mindim::Int = get(kwargs,:mindim,1)
  cutoff::Float64 = get(kwargs,:cutoff,0.0)
  absoluteCutoff::Bool = get(kwargs,:absoluteCutoff,false)
  doRelCutoff::Bool = get(kwargs,:doRelCutoff,true)
  utags = TagSet(get(kwargs,:utags,"Link,u"))
  vtags = TagSet(get(kwargs,:vtags,"Link,v"))
  fastSVD::Bool = get(kwargs,:fastSVD,false)

  if fastSVD
    MU,MS,MV = svd(reshape(data(Astore),dim(Lis),dim(Ris)))
  else
    MU,MS,MV = recursiveSVD(reshape(data(Astore),dim(Lis),dim(Ris)))
  end
  MV = conj!(MV)

  P = MS.^2
  #@printf "  Truncating with maxdim=%d cutoff=%.3E\n" maxdim cutoff
  truncate!(P;mindim=mindim,
              maxdim=maxdim,
              cutoff=cutoff,
              absoluteCutoff=absoluteCutoff,
              doRelCutoff=doRelCutoff)
  dS = length(P)
  if dS < length(MS)
    MU = MU[:,1:dS]
    resize!(MS,dS)
    MV = MV[:,1:dS]
  end

  u = Index(dS,utags)
  v = settags(u,vtags)
  Uis,Ustore = IndexSet(Lis...,u),Dense{T}(vec(MU))
  #TODO: make a diag storage
  Sis,Sstore = IndexSet(u,v),Diag{Vector{Float64}}(MS)
  Vis,Vstore = IndexSet(Ris...,v),Dense{T}(Vector{T}(vec(MV)))

  return (Uis,Ustore,Sis,Sstore,Vis,Vstore)
end

function storage_eigen(Astore::Dense{T},
                       Lis::IndexSet,
                       Ris::IndexSet;
                       kwargs...) where {T}
  maxdim::Int = get(kwargs,:maxdim,min(dim(Lis),dim(Ris)))
  mindim::Int = get(kwargs,:mindim,1)
  cutoff::Float64 = get(kwargs,:cutoff,0.0)
  absoluteCutoff::Bool = get(kwargs,:absoluteCutoff,false)
  doRelCutoff::Bool = get(kwargs,:doRelCutoff,true)
  tags = TagSet(get(kwargs,:lefttags,"Link,u"))
  lefttags = TagSet(get(kwargs,:lefttags,tags))
  righttags = TagSet(get(kwargs,:righttags,prime(lefttags)))

  dim_left = dim(Lis)
  dim_right = dim(Ris)
  MD,MU = eigen(Hermitian(reshape(data(Astore),dim_left,dim_right)))

  # Sort by largest to smallest eigenvalues
  p = sortperm(MD; rev = true)
  MD = MD[p]
  MU = MU[:,p]

  #@printf "  Truncating with maxdim=%d cutoff=%.3E\n" maxdim cutoff
  truncate!(MD;maxdim=maxdim,
              cutoff=cutoff,
              absoluteCutoff=absoluteCutoff,
              doRelCutoff=doRelCutoff)
  dD = length(MD)
  if dD < size(MU,2)
    MU = MU[:,1:dD]
  end

  #TODO: include truncation parameters as keyword arguments
  u = Index(dD,lefttags)
  v = settags(u,righttags)
  Uis,Ustore = IndexSet(Lis...,u),Dense{T}(vec(MU))
  Dis,Dstore = IndexSet(u,v),Diag{Vector{Float64}}(MD)
  return (Uis,Ustore,Dis,Dstore)
end

# TODO: move this to a general "linear_algebra.jl" file?
# i.e. a common place for custom linear algebra functionality
# for matrices
function polar(A::Matrix)
  U,S,V = svd(A) # calls LinearAlgebra.svd()
  return U*V',V*Diagonal(S)*V'
end

function storage_qr(Astore::Dense{T},
                    Lis::IndexSet,
                    Ris::IndexSet;
                    kwargs...) where {T}
  tags = TagSet(get(kwargs,:tags,"Link,u"))
  dim_left = dim(Lis)
  dim_right = dim(Ris)
  MQ,MP = qr(reshape(data(Astore),dim_left,dim_right))
  dim_middle = min(dim_left,dim_right)
  u = Index(dim_middle,tags)
  #Must call Matrix() on MQ since the QR decomposition outputs a sparse
  #form of the decomposition
  Qis,Qstore = IndexSet(Lis...,u),Dense{T}(vec(Matrix(MQ)))
  Pis,Pstore = IndexSet(u,Ris...),Dense{T}(vec(Matrix(MP)))
  return (Qis,Qstore,Pis,Pstore)
end

function storage_polar(Astore::Dense{T},
                       Lis::IndexSet,
                       Ris::IndexSet) where {T}
  dim_left = dim(Lis)
  dim_right = dim(Ris)
  MQ,MP = polar(reshape(data(Astore),dim_left,dim_right))
  dim_middle = min(dim_left,dim_right)
  Uis = prime(Ris)
  Qis,Qstore = IndexSet(Lis...,Uis...),Dense{T}(vec(MQ))
  Pis,Pstore = IndexSet(Uis...,Ris...),Dense{T}(vec(MP))
  return (Qis,Qstore,Pis,Pstore)
end

function storage_exp(As::Dense{T}, Lis,Ris) where {T}
  expAdata = exp( reshape(data(As),dim(Lis),dim(Ris)) )
  return Dense{T}(vec(expAdata))
end
