def ci_bounds(pos, n, power)
    if n == 0
        return 0
    end
    z = Statistics2.pnormaldist(1-power/2)
    phat = 1.0*pos/n
    offset = z * Math.sqrt((phat*(1-phat)+z*z/(4*n))/n)
    denominator = (1+z*z/n)
    return [ (phat + z*z/(2*n) - offset)/denominator,
             (phat + z*z/(2*n) + offset)/denominator ]
end
