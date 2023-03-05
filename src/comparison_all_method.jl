using QCBase
using RDM
using FermiCG
using Printf
using Test
using LinearAlgebra
using Profile
using Random
using PyCall
using Arpack
using JLD2
using Plots
using ClusterMeanField
using ActiveSpaceSolvers



function get_circle_coordinates(center_x, center_y,center_z ,radius, num_points,R,scale1,scale)
    coordinates= []
    for i in 1:num_points
        angle = 2 * π * i / num_points
        x=center_x+0.0
        y=  center_y+ radius * cos(angle)
        z=  center_z+ radius * sin(angle)
        push!(coordinates,[x,y,z])
    end
    
    if R<2
        for i in 1:num_points
            angle = 2 * π * i / num_points+(scale)
            x=center_x+0.0
            y=  center_y+ radius * cos(angle)
            z=  center_z+ radius * sin(angle)
            push!(coordinates,[x,y,z])
        end
    else
        for i in 1:num_points
            angle = 2 * π * i / num_points+(scale1)
            x=center_x+0.0
            y=  center_y+ radius * cos(angle)
            z=  center_z+ radius * sin(angle)
            push!(coordinates,[x,y,z])
        end
    end
    return coordinates

end




#basis="sto-3g"
basis="3-21g"
n_steps = 70
energies_cmf=[]
fci_energies=[]
energies_cmx_tpsci=[]
energies_cmx_bst=[]
energies_pt2_bst=[]
io = open("traj_H6_angle_1.xyz", "w");
angle_num=70



for r in 64:70
    println(r)
    println("\n")
    xyz = @sprintf("%5i\n\n", 6)
    scale1=π/24+(r*π/250)
    c= get_circle_coordinates(0.0,0.0,0.0,2.2,3,r,scale1,π/24)
    tmp=[]
    push!(tmp, Atom(1,"H",[c[1][1], c[1][2], c[1][3]]))
    push!(tmp, Atom(2,"H",[c[4][1], c[4][2], c[4][3]]))
    push!(tmp, Atom(3,"H",[c[2][1], c[2][2], c[2][3]]))
    push!(tmp, Atom(4,"H",[c[5][1], c[5][2], c[5][3]]))
    push!(tmp, Atom(5,"H",[c[3][1], c[3][2], c[3][3]]))
    push!(tmp, Atom(6,"H",[c[6][1], c[6][2], c[6][3]]))
    pymol=Molecule(0,1,tmp,basis)
    for a in tmp
        xyz = xyz * @sprintf("%6s %24.16f %24.16f %24.16f \n", a.symbol, a.xyz[1], a.xyz[2], a.xyz[3])
    end
    println(xyz)
    write(io, xyz);
    clusters=[(1:4),(5:8),(9:12)]   
    #clusters    = [(1:2),(3:4),(5:6)]
    init_fspace = [(1,1),(1,1),(1,1)]
    na = 3
    nb = 3
    nroots = 1



    # get integrals
    mf = pyscf_do_scf(pymol)
    nbas = size(mf.mo_coeff)[1]
    ints = pyscf_build_ints(pymol,mf.mo_coeff, zeros(nbas,nbas));
    nelec = na + nb
    norb = size(ints.h1,1)
    nuc_energy=mf.energy_nuc()



    # localize orbitals
    C = mf.mo_coeff
    Cl = localize(mf.mo_coeff,"lowdin",mf)
    ClusterMeanField.pyscf_write_molden(pymol,Cl,filename="lowdin.molden")
    S = get_ovlp(mf)
    U =  C' * S * Cl
    println(" Rotate Integrals")
    flush(stdout)
    ints = orbital_rotation(ints,U)
    println(" done.")
    flush(stdout)

    println("*************************************************************FCI ENERGY*******************************************************************","\n\n")

    ansatz = FCIAnsatz(norb, na, nb)
    solver = SolverSettings(nroots=1, package="Arpack")
    solution = solve(ints, ansatz, solver)
    display(solution)
    
    println("*************************************************************CMF ENERGY*******************************************************************","\n\n")

    # define clusters
    clusters = [MOCluster(i,collect(clusters[i])) for i = 1:length(clusters)]
    display(clusters)
    rdm1 = zeros(size(ints.h1))
    #d1 = RDM1(n_orb(ints))
    e_cmf, U, d1  = ClusterMeanField.cmf_oo_diis(ints, clusters, init_fspace, RDM1(rdm1, rdm1), verbose=0, diis_start=3)
    #e_cmf, U, d1  = FermiCG.cmf_oo(ints, clusters, init_fspace, d1,
                                    #max_iter_oo=40, verbose=0, gconv=1e-6, method="bfgs")
    ClusterMeanField.pyscf_write_molden(pymol,Cl*U,filename="cmf.molden")
    #println(e_cmf)
    ints = FermiCG.orbital_rotation(ints,U)
    e_ref = e_cmf - ints.h0
    max_roots = 100
    cluster_bases = FermiCG.compute_cluster_eigenbasis(ints, clusters, verbose=0, max_roots=max_roots,
                                                        init_fspace=init_fspace, rdm1a=d1.a, rdm1b=d1.b, T=Float64)
    clustered_ham = FermiCG.extract_ClusteredTerms(ints, clusters)
    cluster_ops = FermiCG.compute_cluster_ops(cluster_bases, ints);
    FermiCG.add_cmf_operators!(cluster_ops, cluster_bases, ints, d1.a, d1.b);
    ref_fock = FermiCG.FockConfig(init_fspace)

    #BST CMX 
    println("*************************************************************BST-CMX ENERGY*******************************************************************","\n\n")


    ψ = FermiCG.BSTstate(clusters, FockConfig(init_fspace), cluster_bases)
    ept2 = FermiCG.compute_pt2_energy(ψ, cluster_ops, clustered_ham, thresh_foi=1e-6,verbose=1)
    total_pt2=ept2[1]+nuc_energy
    println("the value of pt2 correction energy value is",total_pt2)
    display(ψ)
    σ = FermiCG.build_compressed_1st_order_state(ψ, cluster_ops, clustered_ham, nbody=4, thresh=1e-5)
    σ = FermiCG.compress(σ, thresh=1e-4)

    #H = FermiCG.nonorth_dot(ψ,σ) 
    H1 = FermiCG.compute_expectation_value(ψ, cluster_ops, clustered_ham)
    H2 = FermiCG.orth_dot(σ,σ)
    H3 = FermiCG.compute_expectation_value(σ, cluster_ops, clustered_ham)
    sigma2 = FermiCG.build_compressed_1st_order_state(σ, cluster_ops, clustered_ham, nbody=4, thresh=1e-5)
    sigma2_compressed = FermiCG.compress(sigma2, thresh=1e-4)
    H4 = FermiCG.orth_dot(sigma2_compressed,sigma2_compressed)
    H5 = FermiCG.compute_expectation_value(sigma2_compressed, cluster_ops, clustered_ham)



    I_1=H1[1]
    I_2=H2[1]-I_1*H1[1]
    I_3=H3[1]-I_1*H2[1]-2*I_2*H1[1]
    I_4=H4[1]-I_1*H3[1]-3*I_2*H2[1]-3*I_3*H1[1]
    I_5=H5[1]-I_1*H4[1]-4*I_2*H3[1]-6*I_3*H2[1]-4*I_4*H1[1]
    E_K2=I_1-(I_2*I_2/I_3)*(1+(((I_4*I_2-I_3*I_3)^2)/(I_2*I_2*(I_5*I_3-I_4*I_4))))
    cmx_2=E_K2+nuc_energy


    println("*************************************************************TPSCI-CMX ENERGY*******************************************************************","\n\n")

    cmfstate = FermiCG.TPSCIstate(clusters, FockConfig(init_fspace),R=1,T=Float64)
    cmfstate[FermiCG.FockConfig(init_fspace)][FermiCG.ClusterConfig([1,1,1])] = [1.0]
    display(cmfstate)
    sig = FermiCG.open_matvec_thread(cmfstate, cluster_ops, clustered_ham, nbody=4, thresh=1e-6, prescreen=true)
    #display(size(sig))
    FermiCG.clip!(sig, thresh=1e-5)
    #display(size(sig))
    # <H> = (<0|H)|0> = <sig|0>
    H_1 = dot(sig, cmfstate)
    # <HH> = (<0|H)(H|0>) = <sig|sig>
    H_2 = dot(sig, sig)
    # <HHH> = (<0|H)H(H|0>) = <sig|H|sig>
    H_3 = FermiCG.compute_expectation_value_parallel(sig, cluster_ops, clustered_ham)
    # |sig> = H|sig> = HH|0>
    sig = FermiCG.open_matvec_thread(cmfstate, cluster_ops, clustered_ham, nbody=4, thresh=1e-6, prescreen=true)
    FermiCG.clip!(sig, thresh=1e-5)
    # <HHHH> = (<0|HH)(HH|0>) = <sig|sig>
    H_4 = dot(sig, sig)
    # <HHHH> = (<0|HH)H(HH|0>) = <sig|H|sig>
    H_5 = FermiCG.compute_expectation_value_parallel(sig, cluster_ops, clustered_ham)



    I1=H_1[1]
    I2=H_2[1]-I1*H_1[1]
    I3=H_3[1]-I1*H_2[1]-2*I2*H_1[1]
    I4=H_4[1]-I1*H_3[1]-3*I2*H_2[1]-3*I3*H_1[1]
    I5=H_5[1]-I1*H_4[1]-4*I2*H_3[1]-6*I3*H_2[1]-4*I4*H_1[1]
    EK2=I1-(I2*I2/I3)*(1+(((I4*I2-I3*I3)^2)/(I2*I2*(I5*I3-I4*I4))))
    cmx2=EK2+nuc_energy




    push!(energies_cmx_tpsci,cmx2)
    push!(energies_cmx_bst,cmx_2)
    push!(energies_cmf,e_cmf)
    push!(energies_pt2_bst,total_pt2)
    push!(fci_energies,solution.energies[1])

    
end
println(energies_cmf)
println(energies_cmx_bst)
println(energies_cmx_tpsci)
println(fci_energies)
println(energies_pt2_bst)
close(io)

plot([energies_cmf.-energies_cmf[end], energies_cmx_bst.-energies_cmx_bst[end], energies_cmx_tpsci.-energies_cmx_tpsci[end],energies_pt2_bst.-energies_pt2_bst[end],fci_energies.-fci_energies[end]]*627.51, labels = ["CMF" "CMX-BST" "CMX-TPSCI" "BST-PT2" "FCI"])
#savefig("plot_H6_ring.png")