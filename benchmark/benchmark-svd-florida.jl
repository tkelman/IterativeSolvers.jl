#!/usr/bin/env julia
#
# Benchmarking script for singular value problems
Pkg.installed("Benchmarks")==nothing &&
    Pkg.clone("https://github.com/johnmyleswhite/Benchmarks.jl")
using Benchmarks
using IterativeSolvers
using JLD
using MAT

BASEDIR = "florida"

for group in readdir(BASEDIR)
    isdir(joinpath(BASEDIR, group)) || continue
    for matrix in readdir(joinpath(BASEDIR, group))
        filename = joinpath(BASEDIR, group, matrix)

        endswith(matrix, ".mat") || continue

	#If we already saved benchmarks, don't rerun
	benchmarkfilename = joinpath(BASEDIR, group, matrix[1:end-3]*"jld")
	isfile(benchmarkfilename) && continue

	#To debug this script, it's useful to run it on small matrices only
	#filesize(filename) < 10000 || continue

        mf = matread(filename)
        if !haskey(mf, "Problem")
            warn("Skipping unknown file $filename: No 'Problem' struct")
            continue
        end
	
        pr = mf["Problem"]
        if !haskey(pr, "A")
            warn("Skipping unknown file $filename: 'Problem' struct has no matrix 'A'")
            continue
        end
        A = pr["A"]

        #eltype(A) <: Real || warn("Skipping matrix with unsupported element type $(eltype(A))")
        info(filename*", size = $(size(A))")
        
	m, n = size(A)
	#Choose the same normalized unit vector to start with
	q = randn(n)
        eltype(A) <: Complex && (q += im*randn(n))
        scale!(q, inv(norm(q)))

        #Number of singular values to request
        nv = min(m, n, 10)

        #Maximum number of iterations
        maxiter = max(m, n)

        #Tolerance, however the algorithm chooses to interpret this
	#Set convergence criterion to sqrt eps
	tol = √eps(real(one(eltype(A))))

        #info("Running naive SVD")
        #@time svdvals_gkl(A, 10)

        info("svds (eigs on [0 A; A' 0])")
	b_svds = @benchmark svds(A, nsv=nv, tol=tol, maxiter=maxiter)
        
	info("eigs on A'A or AA'")
	b_ata = @benchmark B = m≥n ? A*A' : A'A
	B = m≥n ? A*A' : A'A
	b_eigs = @benchmark eigs(B, nev=nv, tol=tol, maxiter=maxiter)

        info("GKL with thick restart using Ritz values")
        b_tr = try
            @benchmark svdvals_tr(A, q, nv, tol=tol, reltol=tol)
        catch exc
            println("Exception: $exc")
        end
        
	info("GKL with thick restart using harmonic Ritz values")
        b_trh = try
            @benchmark svdvals_tr(A, q, nv, tol=tol, reltol=tol, method=:harmonic)
        catch exc
            println("Exception: $exc")
        end

	
	data = Dict(
	    "svds" => b_svds,
	    "ata" => b_ata,
	    "eigs" => b_eigs,
	    "tr" => b_tr,
	    "trh" => b_trh
	)
	println("Timings:")
	for (k, v) in data
	    println(k)
	    display(v)
	    println()
        end
        JLD.save(benchmarkfilename, data, compress=true)
    end
end