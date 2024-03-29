using ClusterMeanField
using RDM
using QCBase
using PyCall
using Printf
using InCoreIntegrals
using LinearAlgebra
using FermiCG
pyscf=pyimport("pyscf")
np=pyimport("numpy")
symm=pyimport("pyscf.symm")
scf_energy=[]
atoms = []
r0 = 0.8 
push!(atoms,Atom(1,"N", [0.0, 0.0, 0.0]))
push!(atoms,Atom(2,"N", [1.1, 0.0, 0.0]))

basis = "6-31G"
basis="sto3g"

molecule = """
    N   0.0 0.0 0.0
    N   1.15 0.0 0.0
    """
print(molecule)
    
mol = pyscf.gto.Mole(
    atom    =   molecule,
    symmetry=true,
    spin    =   0,
    charge  =   0,
    basis   =   basis)
mol.build()
mf = pyscf.scf.ROHF(mol)
mf.verbose = 4
mf.conv_tol = 1e-8
mf.conv_tol_grad = 1e-5
mf.chkfile = "scf.fchk"
mf.init_guess = "sad"
mf.run(max_cycle=200)
println(" Hartree-Fock Energy: ",mf.e_tot)
norb =size(mf.mo_coeff)[1]
println(norb)

pymol = Molecule(0,1,atoms,basis)
ClusterMeanField.pyscf_write_molden(pymol, mf.mo_coeff,filename="C_RHF_n2.molden")
# localize orbitals
C = mf.mo_coeff
Cl = localize(mf.mo_coeff,"lowdin",mf)
ClusterMeanField.pyscf_write_molden(pymol,Cl,filename="lowdin_n2_sto3g.molden")


#getting the clusters for the active space
clusters = [[2,3,4,5],[7,8,9,10]]

println(norb)
#specify frozen core
frozen= [1,6]  
c_frozen=Cl[:,frozen]
d_frozen=2*c_frozen*c_frozen'
function c_act(orb_no,cluster,coeff)
    C_ordered = zeros(orb_no,0)
    for (ci,c) in enumerate(cluster)
        C_ordered = hcat(C_ordered, coeff[:,c])
    end
    return C_ordered
end
#get the active ActiveSpace 
C_act=c_act(norb,clusters,Cl)
pyscf.tools.molden.from_mo(mol, "C_ordered_n2_sto3g.molden", C_act)
#specify the clusters and initial fock space electrons
init_fspace = [(3,2),(2,3)]

clusters_1=[(1:4),(5:8)]

println(clusters_1)
println(init_fspace)
for ci in clusters_1
    print(length(ci))
end
#pyscf.scf.hf_symm.analyze(mf)
mol_1=make_pyscf_mole(pymol)
#making the integrals
#ints=ClusterMeanField.pyscf_build_ints(pymol,C_act,d_frozen)
h0 = pyscf.gto.mole.energy_nuc(mol_1)
nuc_energy= pyscf.gto.mole.energy_nuc(mol_1)
h  = pyscf.scf.hf.get_hcore(mol_1)
j, k = pyscf.scf.hf.get_jk(mol_1, d_frozen, hermi=1)
h0 += tr(d_frozen * ( h + .5*j - .25*k))
# now rotate to MO basis
h = C_act' * h * C_act
j = C_act' * j * C_act
k = C_act' * k * C_act
s= mol_1.intor("int1e_ovlp_sph")
n_act = size(C_act)[2]
h2 = pyscf.ao2mo.kernel(mol_1, C_act, aosym="s4",compact=false)
h2 = reshape(h2, (n_act, n_act, n_act, n_act))
nact=tr(s*d_frozen*s*C_act*C_act')
println(nact)
h1 = h + j - .5*k
ints = InCoreInts(h0, h1, h2)
#ints=ClusterMeanField.pyscf_build_ints(pymol,C_act)
na =7
nb=7
nelec= na +nb


#cmf section
clusters_2 = [MOCluster(i,collect(clusters_1[i])) for i = 1:length(clusters_1)]
display(clusters_2)
rdm1 = zeros(size(ints.h1))
println(size(rdm1))
#d1 = RDM1(n_orb(ints))
e_cmf, U, d1  = ClusterMeanField.cmf_oo_diis(ints, clusters_2, init_fspace, RDM1(rdm1, rdm1), verbose=0, maxiter_oo=800,maxiter_ci=400, diis_start=5)
#e_cmf, U, d1  = ClusterMeanField.cmf_oo(ints, clusters, init_fspace, d1,
                                    #max_iter_oo=100, verbose=0, gconv=1e-6, method="bfgs")
ClusterMeanField.pyscf_write_molden(pymol,C_act*U,filename="cmf_n2_sto3g.molden")


bst_cmx=[]
cmf=[]
scf=[]
pt2=[]
cepa=[]
for r in 1:30
    atoms = []
    scale=0.8+r*0.04
    push!(atoms,Atom(1,"N", [0.0, 0.0, 0.0]))
    push!(atoms,Atom(2,"N", [scale, 0.0, 0.0]))

    #basis = "6-31G"
    basis="sto3g"

    molecule=@sprintf("%6s %24.16f %24.16f %24.16f \n","N", 0.0, 0.0, 0.0)
    molecule=molecule*@sprintf("%6s %24.16f %24.16f %24.16f \n", "N", scale, 0.0, 0.0)
    print(molecule)
    mol = pyscf.gto.Mole(
    atom    =   molecule,
    symmetry=true,
    spin    =   0,
    charge  =   0,
    basis   =   basis)
    mol.build()
    mf = pyscf.scf.ROHF(mol)
    mf.verbose = 4
    mf.conv_tol = 1e-8
    mf.conv_tol_grad = 1e-5
    mf.chkfile = "scf.fchk"
    mf.init_guess = "sad"
    mf.run(max_cycle=200)
    println(" Hartree-Fock Energy: ",mf.e_tot)
    norb =size(mf.mo_coeff)[1]
    println(norb)

    pymol = Molecule(0,1,atoms,basis)
    ClusterMeanField.pyscf_write_molden(pymol, mf.mo_coeff,filename="C_RHF_n2.molden")
    # localize orbitals
    C = mf.mo_coeff
    Cl = localize(mf.mo_coeff,"lowdin",mf)
    ClusterMeanField.pyscf_write_molden(pymol,Cl,filename="lowdin_n2_sto3g.molden")


    #getting the clusters for the active space
    clusters = [[2,3,4,5],[7,8,9,10]]

    println(norb)
    #specify frozen core
    frozen= [1,6]  
    c_frozen=Cl[:,frozen]
    d_frozen=2*c_frozen*c_frozen'
    function c_act(orb_no,cluster,coeff)
        C_ordered = zeros(orb_no,0)
        for (ci,c) in enumerate(cluster)
            C_ordered = hcat(C_ordered, coeff[:,c])
        end
        return C_ordered
    end
    #get the active ActiveSpace 
    C_act=c_act(norb,clusters,Cl)
    pyscf.tools.molden.from_mo(mol, "C_ordered_n2_sto3g.molden", C_act)
    #specify the clusters and initial fock space electrons
    init_fspace = [(3,2),(2,3)]

    clusters_1=[(1:4),(5:8)]

    println(clusters_1)
    println(init_fspace)
    for ci in clusters_1
        print(length(ci))
    end
    #pyscf.scf.hf_symm.analyze(mf)
    mol_1=make_pyscf_mole(pymol)
    #making the integrals
    #ints=ClusterMeanField.pyscf_build_ints(pymol,C_act,d_frozen)
    h0 = pyscf.gto.mole.energy_nuc(mol_1)
    nuc_energy= pyscf.gto.mole.energy_nuc(mol_1)
    h  = pyscf.scf.hf.get_hcore(mol_1)
    j, k = pyscf.scf.hf.get_jk(mol_1, d_frozen, hermi=1)
    h0 += tr(d_frozen * ( h + .5*j - .25*k))
    # now rotate to MO basis
    h = C_act' * h * C_act
    j = C_act' * j * C_act
    k = C_act' * k * C_act
    s= mol_1.intor("int1e_ovlp_sph")
    n_act = size(C_act)[2]
    h2 = pyscf.ao2mo.kernel(mol_1, C_act, aosym="s4",compact=false)
    h2 = reshape(h2, (n_act, n_act, n_act, n_act))
    nact=tr(s*d_frozen*s*C_act*C_act')
    println(nact)
    h1 = h + j - .5*k
    ints = InCoreInts(h0, h1, h2)
    #ints=ClusterMeanField.pyscf_build_ints(pymol,C_act)
    na =7
    nb=7
    nelec= na +nb


    #cmf section
    clusters_2 = [MOCluster(i,collect(clusters_1[i])) for i = 1:length(clusters_1)]
    display(clusters_2)
    rdm1 = zeros(size(ints.h1))
    println(size(rdm1))
    #d1 = RDM1(n_orb(ints))
    e_cmf, U, d1  = ClusterMeanField.cmf_oo_diis(ints, clusters_2, init_fspace, RDM1(rdm1, rdm1), verbose=0, maxiter_oo=800,maxiter_ci=400, diis_start=5)
    println(e_cmf)
    push!(cmf,e_cmf)



    ints = FermiCG.orbital_rotation(ints,U)
    e_ref = e_cmf - ints.h0
    max_roots = 100
    ref_fock = FermiCG.FockConfig(init_fspace)
    cluster_bases = FermiCG.compute_cluster_eigenbasis(ints, clusters_2, verbose=0, max_roots=max_roots,
                                                            init_fspace=init_fspace, rdm1a=d1.a, rdm1b=d1.b, T=Float64)
    #cluster_bases=FermiCG.compute_cluster_eigenbasis_spin(ints,clusters_2,d1,[6,2,2],ref_fock,verbose=1,max_roots=max_roots)
    clustered_ham = FermiCG.extract_ClusteredTerms(ints, clusters_2)
    cluster_ops = FermiCG.compute_cluster_ops(cluster_bases, ints);
    FermiCG.add_cmf_operators!(cluster_ops, cluster_bases, ints, d1.a, d1.b);
    



    #BST CMX 
    println("*************************************************************BST-CMX ENERGY*******************************************************************","\n\n")  
    #forming bst wavefunction
    ψ = FermiCG.BSTstate(clusters_2, FockConfig(init_fspace), cluster_bases)
    e_cepa, v_cepa = FermiCG.do_fois_cepa(ψ , cluster_ops, clustered_ham, thresh_foi=1e-3, max_iter=50, tol=1e-8)
    display(e_cepa+ints.h0)
    push!(cepa,e_cepa+ints.h0)


    #pt2_correction 
    #ept2 = FermiCG.compute_pt2_energy(ψ, cluster_ops, clustered_ham, thresh_foi=1e-6,tol=1e-6,verbose=1)
    #total_pt2=ept2[1]+ints.h0
    #println("the value of pt2 correction energy value is",total_pt2)
    #push!(pt2,total_pt2)
    display(ψ)



    #calculating hamiltonians
    σ = FermiCG.build_compressed_1st_order_state(ψ, cluster_ops, clustered_ham, nbody=4, thresh=1e-9)
    σ = FermiCG.compress(σ, thresh=1e-9)
    H1 = FermiCG.compute_expectation_value(ψ, cluster_ops, clustered_ham)
    H2 = FermiCG.orth_dot(σ,σ)
    H3 = FermiCG.compute_expectation_value(σ, cluster_ops, clustered_ham)
    sigma2 = FermiCG.build_compressed_1st_order_state(σ, cluster_ops, clustered_ham, nbody=4, thresh=1e-9)
    sigma2_compressed = FermiCG.compress(sigma2, thresh=1e-9)
    H4 = FermiCG.orth_dot(sigma2_compressed,sigma2_compressed)
    H5 = FermiCG.compute_expectation_value(sigma2_compressed, cluster_ops, clustered_ham)

    #calculating moments and cmx energy
    I_1=H1[1]
    I_2=H2[1]-I_1*H1[1]
    I_3=H3[1]-I_1*H2[1]-2*I_2*H1[1]
    I_4=H4[1]-I_1*H3[1]-3*I_2*H2[1]-3*I_3*H1[1]
    I_5=H5[1]-I_1*H4[1]-4*I_2*H3[1]-6*I_3*H2[1]-4*I_4*H1[1]
    E_K2=I_1-(I_2*I_2/I_3)*(1+(((I_4*I_2-I_3*I_3)^2)/(I_2*I_2*(I_5*I_3-I_4*I_4))))
    cmx_2=E_K2+ints.h0
    println(cmx_2)
    push!(bst_cmx,cmx_2)
    println("\n\n",r,"\n\n")
    push!(scf,mf.e_tot)
    println(scf)
    println(cmf)
    println(bst_cmx)
    println(cepa)
    #println(pt2)
end

