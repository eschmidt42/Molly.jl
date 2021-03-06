"""
    Mie(m, n, nl_only)

The Mie generalized interaction.
When `m` equals 6 and `n` equals 12 this is equivalent to the Lennard Jones interaction.
"""
struct Mie{S, C, T} <: GeneralInteraction
    m::T
    n::T
    cutoff::C
    nl_only::Bool
    mn_fac::T
end

Mie{S}(m, n, cutoff, nl_only, mn_fac) where S =
    Mie{S, typeof(cutoff), typeof(m)}(m, n, cutoff, nl_only, mn_fac)

Mie(m, n, cutoff, nl_only, mn_fac) =
    Mie{false, typeof(cutoff), typeof(m)}(m, n, cutoff, nl_only, mn_fac)

Mie(m, n, nl_only=false) = Mie(m, n, ShiftedPotentialCutoff(3.0), nl_only,
                                convert(typeof(m), (n / (n - m)) * (n / m) ^ (m / (n - m))))

@fastmath @inbounds function force(inter::Mie{S, C, T},
                                    coord_i,
                                    coord_j,
                                    atom_i,
                                    atom_j,
                                    box_size) where {S, C, T}
    dr = vector(coord_i, coord_j, box_size)
    r2 = sum(abs2, dr)
    r = √r2

    if !S && iszero(atom_i.σ) || iszero(atom_j.σ)
        return zero(coord_i)
    end

    σ = sqrt(atom_i.σ * atom_j.σ)
    ϵ = sqrt(atom_i.ϵ * atom_j.ϵ)

    cutoff = inter.cutoff
    m = inter.m
    n = inter.n
    # Derivative obtained via wolfram
    const_mn = inter.mn_fac * ϵ
    σ_r = σ / r
    σ2 = σ^2
    params = (m, n, σ_r, const_mn)

    if cutoff_points(C) == 0
        f = force_nocutoff(inter, r2, inv(r2), params)
    elseif cutoff_points(C) == 1
        sqdist_cutoff = cutoff.sqdist_cutoff * σ2
        r2 > sqdist_cutoff && return zero(coord_i)

        f = force_cutoff(cutoff, r2, inter, params)
    elseif cutoff_points(C) == 2
        sqdist_cutoff = cutoff.sqdist_cutoff * σ2
        activation_dist = cutoff.activation_dist * σ2

        r2 > sqdist_cutoff && return zero(coord_i)

        if r2 < activation_dist
            f = force_nocutoff(inter, r2, inv(r2), params)
        else
            f = force_cutoff(cutoff, r2, inter, params)
        end
    end

    return f * dr
end

@fastmath function force_nocutoff(::Mie, r2, invr2, (m, n, σ_r, const_mn))
    return -const_mn / r2 * (m * σ_r ^ m - n * σ_r ^ n)
end

@inline @inbounds function potential_energy(inter::Mie{S, C, T},
                                            s::Simulation,
                                            i::Integer,
                                            j::Integer) where {S, C, T}
    U = eltype(s.coords[i]) # this is not Unitful compatible
    i == j && return zero(T)

    dr = vector(s.coords[i], s.coords[j], s.box_size)
    r2 = sum(abs2, dr)
    r = √r2

    if !S && iszero(s.atoms[i].σ) || iszero(s.atoms[j].σ)
        return zero(U)
    end

    σ = sqrt(s.atoms[i].σ * s.atoms[j].σ)
    ϵ = sqrt(s.atoms[i].ϵ * s.atoms[j].ϵ)

    cutoff = inter.cutoff
    m = inter.m
    n = inter.n
    const_mn = inter.mn_fac * ϵ
    σ_r = σ / r
    σ2 = σ^2
    params = (m, n, σ_r, const_mn)

    if cutoff_points(C) == 0
        potential(inter, r2, inv(r2), params)
    elseif cutoff_points(C) == 1
        sqdist_cutoff = cutoff.sqdist_cutoff * σ2
        r2 > sqdist_cutoff && return zero(U)

        potential_cutoff(cutoff, r2, inter, params)
    elseif cutoff_points(C) == 2
        r2 > sqdist_cutoff && return zero(U)

        if r2 < activation_dist
            potential(inter, r2, inv(r2), params)
        else
            potential_cutoff(cutoff, r2, inter, params)
        end
    end
end

@fastmath function potential(::Mie, r2, invr2, (m, n, σ_r, const_mn))
    return const_mn * (σ_r ^ m - σ_r ^ m)
end
