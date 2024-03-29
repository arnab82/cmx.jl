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


function get_circle_coordinates(center_x, center_y,center_z ,radius, num_points,R)
    coordinates= []
    for i in 1:num_points
        angle = 2 * π * i / num_points
        x=center_x+0.0
        y=  center_y+ radius * cos(angle)
        z=  center_z+ radius * sin(angle)
        push!(coordinates,[x,y,z])
    end
    if R<2
        scale1=R*π/18
    elseif 1<R<4
        scale1=R*π/35
    elseif 3<R<6
        scale1=R*π/46
    else 
        scale1=R*π/55
    end
    if scale1<(2*π/9)
        for i in 1:num_points
            angle = 2 * π * i / num_points+(scale1)
            x=center_x+0.0
            y=  center_y+ radius * cos(angle)
            z=  center_z+ radius * sin(angle)
            push!(coordinates,[x,y,z])
        end
    elseif scale1>(2*π/9)
        for i in 1:num_points
            angle = 2 * π * i / num_points+(scale1-π/36)
            x=center_x+0.0
            y=  center_y+ radius * cos(angle)
            z=  center_z+ radius * sin(angle)
            push!(coordinates,[x,y,z])
        end
    end
    return coordinates

end
function get_circle_coordinates_long(center_x, center_y,center_z ,radius, num_points,R)
    coordinates= []
    for i in 1:num_points
        angle = 2 * π * i / num_points
        x=center_x+0.0
        y=  center_y+ radius * cos(angle)
        z=  center_z+ radius * sin(angle)
        push!(coordinates,[x,y,z])
    end
    if R<2
        scale1=R*π/36
    else 
        scale1=R*π/70
    end
    if scale1<(π/4)
        for i in 1:num_points
            angle = 2 * π * i / num_points+(scale1)
            x=center_x+0.0
            y=  center_y+ radius * cos(angle)
            z=  center_z+ radius * sin(angle)
            push!(coordinates,[x,y,z])
        end
    else
        for i in 1:num_points
            angle = 2 * π * i / num_points+(scale1-π/36)
            x=center_x+0.0
            y=  center_y+ radius * cos(angle)
            z=  center_z+ radius * sin(angle)
            push!(coordinates,[x,y,z])
        end
    end
    return coordinates

end


basis="sto-3g"
n_steps = 50
step_size = .03
energies_cmf=[]
io = open("traj_H8_RING.xyz", "w");
for R in 1:n_steps
    scale = 1+R*step_size
    if R<21
        angle_num=12
    elseif 20<R<41
        angle_num=16
    else
        angle_num=20
    end
    for r in 1:angle_num
        xyz = @sprintf("%5i\n\n", 8)
        if R<20
            c= get_circle_coordinates(0.0,0.0,0.0,1.6*scale,4,r)
        else 
            c= get_circle_coordinates_long(0.0,0.0,0.0,1.6*scale,4,r)
        end
        #println(c) 
        tmp=[]
        push!(tmp, Atom(1,"H",[c[1][1], c[1][2], c[1][3]]))
        push!(tmp, Atom(2,"H",[c[5][1], c[5][2], c[5][3]]))
        push!(tmp, Atom(3,"H",[c[2][1], c[2][2], c[2][3]]))
        push!(tmp, Atom(4,"H",[c[6][1], c[6][2], c[6][3]]))
        push!(tmp, Atom(5,"H",[c[3][1], c[3][2], c[3][3]]))
        push!(tmp, Atom(6,"H",[c[7][1], c[7][2], c[7][3]]))
        push!(tmp, Atom(7,"H",[c[4][1], c[4][2], c[4][3]]))
        push!(tmp, Atom(8,"H",[c[8][1], c[8][2], c[8][3]]))
        #println(tmp)
        pymol=Molecule(0,1,tmp,basis)
        for a in tmp
            xyz = xyz * @sprintf("%6s %24.16f %24.16f %24.16f \n", a.symbol, a.xyz[1], a.xyz[2], a.xyz[3])
        end
        println(xyz)
        write(io, xyz);
        
    end
end
close(io)
