*  #[ fitgpdcov:
        subroutine fitgpdcov(xx,yrs,ntot,a,b,xi,alpha,beta,j1,j2
     +       ,lweb,ntype,lchangesign,yr1a,yr2a,xyear,cov1,cov2,offset
     +       ,t,t25,t975,tx,tx25,tx975,threshold,inrestrain,assume
     +       ,lboot,lprint,plot,lwrite)
*
*       fit a GPD distribution to the data, which is already assumed to be declustered
*       input:
*       xx(2,ntot) data,covariate
*       j1,j2    use days/months/... j1 to j2
*       year     leave out this year from teh fit and compute return time for it
*       xyear    value for year, has been set to undef in the series
*       inrestrain restrain xi parameter by adding a normal distribution of width 0.5*inrestrain to the cost function
*       threshold in percent
*       assume   shift: only vary threshold, scale: vary threshold & b in unison, both: independently
*       output
*       a,b,xi,alpha,beta     parameters of fit
*       assume   shift: alpha modifies the position parameter a(cov) = a + alpha*cov
*                scale: alpha modifies both the position and shape parameters:
*                       a(cov) = a*exp(alpha*cov), b(cov) = b*exp(alpha*cov)
*                both:  a(cov) = a + alpha*cov, b(cov) = b + beta*cov
*       t(10,3)    return values for 10, 20, 50, ..., 10000 years for cov=cov1,cov2 and the difference
*       t25,t975   2.5%, 97.5% quantiles of these return values
*       tx(3)      return time of the value of year (xyear) in the context of the other values and difference
*       tx25,tx975 2.5%, 97.5% quantiles of these return times and their differences
*
        implicit none
*
        integer nmc
        parameter(nmc=1000)
        integer ntot,j1,j2,ntype,yr1a,yr2a
        integer yrs(0:ntot)
        real xx(2,ntot),a,b,xi,alpha,beta,xyear,cov1,cov2,offset,
     +       inrestrain,t(10,3),t25(10,3),t975(10,3),
     +       tx(3),tx25(3),tx975(3),ttt(10,3),txtxtx(3),threshold
        character*(*) assume
        logical lweb,lchangesign,lboot,lprint,plot,lwrite
*
        integer i,j,k,l,n,nx,iter,iens,nfit,year
        real x,aa(nmc),bb(nmc),xixi(nmc),alphaalpha(nmc),betabeta(nmc)
     +       ,tt(nmc,10,3),b25,b975,xi25,xi975,alpha25,alpha975
     +       ,t5(10,3),t1(10,3),db,dxi,f,z,ll,ll1,txtx(nmc,3)
     +       ,a25,a975,beta25,beta975,ranf,mean,sd,dalpha,dbeta
     +       ,mindata,minindx,pmindata,snorm,s,xmin
        real adev,var,skew,curt,aaa,siga,chi2,q
        integer,allocatable :: ii(:)
        real,allocatable :: yy(:),ys(:),zz(:),sig(:)
        character lgt*4
*
        integer nmax,ncur
        parameter(nmax=100000)
        real data(2,nmax),restrain
        logical llwrite
        common /fitdata3/ data
        common /fitdata2/ restrain,ncur,llwrite
        character cassume*5
        common /fitdata4/ cassume
        integer nthreshold
        real athreshold,pthreshold
        common /fitdata5/ nthreshold,athreshold,pthreshold
*
        real llgpdcov,gpdcovreturnlevel,gpdcovreturnyear
        external llgpdcov,gpdcovreturnlevel,gpdcovreturnyear
*
        year = yr2a
        if ( lwrite ) then
            print *,'fitgpdcov: input:'
            print *,'assume         = ',assume
            print *,'j1,j2          = ',j1,j2
            print *,'threshold      = ',threshold,'%'
            print *,'year,xyear     = ',year,xyear
            print *,'cov1,cov2,offset ',cov1,cov2,offset
            if ( .false. ) then
                do i=1,ntot
                    print *,i,(xx(j,i),j=1,2)
                enddo
            endif
        endif
!
!       thin data to exclude all the values equal to xmin (result of declustering)
!
        xmin = 3e33
        do i=1,ntot
            xmin = min(xmin,xx(1,i))
        end do
        ncur = 0
        do i=1,ntot
            if ( xx(1,i).gt.xmin ) then
                ncur = ncur + 1
            end if
        end do
*
*       compute first-guess parameters
*
        allocate(ii(ncur))
        allocate(yy(ncur))
        allocate(ys(ncur))
        allocate(zz(ncur))
        allocate(sig(ncur))
        j = 0
        do i=1,ntot
            if ( xx(1,i).gt.xmin ) then
                j = j + 1
                ii(j) = i
                yy(j) = xx(1,i)
                zz(j) = xx(2,i)
            end if
        end do
        if ( j.ne.ncur ) then
            write(0,*) 'fitgpdcov: error: j != ncur ',j,ncur
            write(*,*) 'fitgpdcov: error: j != ncur ',j,ncur
            call abort
        end if
        sig = 0
        call moment(yy,ncur,mean,adev,sd,var,skew,curt)
        call fit(zz,yy,ncur,sig,0,aaa,alpha,siga,dalpha,chi2,q)
        if ( lwrite ) then
            print *,'fitgpdcov: computed initialisation values:'
            print *,'mean,sd,alpha,dalpha = ',mean,sd,alpha,dalpha
        end if
*
*       ill-defined case
*
        if ( sd.eq.0 ) then
            a = 3e33
            b = 3e33
            xi = 3e33
            alpha = 3e33
            beta = 3e33
            t = 3e33
            t25 = 3e33
            t975 = 3e33
            tx = 3e33
            tx25 = 3e33
            tx975 = 3e33
            return
        endif
*
*       copy to common for routine llgpdcov
*
*       number of points above threshold, threshold is relative to the full set (ntot)
        nthreshold = nint(ntot*(1-threshold/100))
        if ( nthreshold.lt.10 ) then
            write(0,*) 'fitgpdcov: error: not enough points above '//
     +           'threshold: ',nthreshold
            write(*,*) 'fitgpdcov: error: not enough points above '//
     +           'threshold: ',nthreshold
            call abort
        end if
        do i=1,ncur
            data(:,i) = xx(:,ii(i))
        enddo
        restrain = inrestrain
        llwrite = lwrite
        cassume = assume

        ! first guess
        ys(1:ncur) = yy(1:ncur)
        call nrsort(ncur,yy)
        athreshold = (yy(ncur-nthreshold) + yy(ncur-nthreshold+1))/2
        ! needed later on...
        yy(1:ncur) = ys(1:ncur)
        b = sd ! should set the scale roughly right...
        xi = 0
        if ( assume.eq.'shift' .or. assume.eq.'scale' ) then
            beta = 3e33
            call fit1gpdcov(a,b,xi,alpha,dalpha,iter)
        else if ( assume.eq.'both' ) then
            beta = alpha
            dbeta = dalpha
            call fit2gpdcov(a,b,xi,alpha,beta,dalpha,dbeta,iter)
        else
            write(0,*) 'fitgpdcov: error: unknown value for assume ',
     +           assume
        end if
        call getreturnlevels(a,b,xi,alpha,beta,cov1,cov2,
     +       gpdcovreturnlevel,j1,j2,t)
        if ( xyear.lt.1e33 ) then
            call getreturnyears(a,b,xi,alpha,beta,xyear,cov1,cov2,
     +           gpdcovreturnyear,j1,j2,tx,lwrite)
        endif
*
*       bootstrap to find error estimates
*
        if ( .not.lboot ) then
            if ( lchangesign ) then
                b = -b
                t = -t
                alpha = -alpha
                if ( assume.eq.'both' ) beta = -beta
            endif
            return
        endif
        if ( .not.lweb ) print '(a,i6,a)','# doing a ',nmc
     +        ,'-member bootstrap to obtain error estimates'
        do iens=1,nmc
            if ( .not.lweb .and. mod(iens,100).eq.0 )
     +           print '(a,i6)','# ',iens
            do i=1,ncur
                call random_number(ranf)
                j = 1+int(ncur*ranf)
                if ( j.lt.1 .or. j.gt.ntot ) then
                    write(0,*) 'fitgpd: error: j = ',j
                    call abort
                endif
                data(:,i) = xx(:,ii(j))
            enddo
            aa(iens) = a
            bb(iens) = b
            xixi(iens) = xi
            alphaalpha(iens) = alpha
            llwrite = .false.
            if ( assume.eq.'shift' .or. assume.eq.'scale' ) then
                betabeta(iens) = 3e33
                call fit1gpdcov(aa(iens),bb(iens),xixi(iens),
     +               alphaalpha(iens),dalpha,iter)
            else if ( assume.eq.'both' ) then
                betabeta(iens) = beta
                call fit2gpdcov(aa(iens),bb(iens),xixi(iens),
     +               alphaalpha(iens),betabeta(iens),dalpha,dbeta,iter)
            else
                write(0,*) 'fitgpdcov: error: unknown value for assume '
     +               ,assume
            end if
            call getreturnlevels(aa(iens),bb(iens),xixi(iens),
     +           alphaalpha(iens),betabeta(iens),
     +           cov1,cov2,gpdcovreturnlevel,j1,j2,ttt)
            do i=1,10
                do j=1,3
                    tt(iens,i,j) = ttt(i,j)
                end do
            end do
            if ( xyear.lt.1e33 ) then
                call getreturnyears(aa(iens),bb(iens),xixi(iens),
     +               alphaalpha(iens),betabeta(iens),xyear,cov1,cov2,
     +               gpdcovreturnyear,j1,j2,txtxtx,lwrite)
                do j=1,3
                    txtx(iens,j) = txtxtx(j)
                end do
            endif
        enddo
        if ( lchangesign ) then
            a = -a
            aa = -aa
            b = -b
            bb = -bb
            alpha = -alpha
            alphaalpha = -alphaalpha
            if ( assume.eq.'both' ) then
                beta = -beta
                betabeta = -betabeta
            end if
            t = -t
            tt = -tt
        endif
        call getcut( a25, 2.5,nmc,aa)
        call getcut(a975,97.5,nmc,aa)
        call getcut( b25, 2.5,nmc,bb)
        call getcut(b975,97.5,nmc,bb)
        call getcut( xi25, 2.5,nmc,xixi)
        call getcut(xi975,97.5,nmc,xixi)
        call getcut( alpha25, 2.5,nmc,alphaalpha)
        call getcut(alpha975,97.5,nmc,alphaalpha)
        if ( assume.eq.'both' ) then
            call getcut( beta25, 2.5,nmc,betabeta)
            call getcut(beta975,97.5,nmc,betabeta)
        end if
        do i=1,10
            do j=1,3
                if ( lchangesign ) then
                    lgt = '&lt;'
                    call getcut(t5(i,j),5.,nmc,tt(1,i,j))
                    call getcut(t1(i,j),1.,nmc,tt(1,i,j))
                else
                    lgt = '&gt;'
                    call getcut(t5(i,j),95.,nmc,tt(1,i,j))
                    call getcut(t1(i,j),99.,nmc,tt(1,i,j))
                endif
                call getcut(t25(i,j),2.5,nmc,tt(1,i,j))
                call getcut(t975(i,j),97.5,nmc,tt(1,i,j))
            enddo
        end do
        do j=1,3
            if ( xyear.lt.1e33 ) then
                call getcut(tx25(j), 2.5,nmc,txtx(1,j))
                call getcut(tx975(j),97.5,nmc,txtx(1,j))
                if ( lchangesign ) xyear = -xyear
            endif
        end do
*
*       output
*
        if ( .not.lprint .and. .not.lwrite ) return
        if ( lweb ) then
            print '(a)','# <tr><td colspan="4">Fitted to GPD '//
     +           'distribution H(x+a'') = 1 - (1+&xi;*x/b'')^(-1/&xi;)'
     +           //'</td></tr>'
            call printab(lweb)
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           'a:</td><td>',a,'</td><td>',a25,'...',a975,'</td></tr>'
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           'b:</td><td>',b,'</td><td>',b25,'...',
     +           b975,'</td></tr>'
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           '&xi;:</td><td>',xi,'</td><td>',xi25,'...',xi975,
     +           '</td></tr>'
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           '&alpha;:</td><td>',alpha,'</td><td>',alpha25,'...',
     +           alpha975,'</td></tr>'
            if ( assume.eq.'both' ) then
                print '(a,f16.3,a,f16.3,a,f16.3,a)',
     +               '# <tr><td colspan=2>&beta;:</td><td>',beta,
     +               '</td><td>',beta25,'...',beta975,'</td></tr>'
            end if
        else
            print '(a,i5,a)','# Fitted to GPD distribution in ',iter
     +           ,' iterations'
            print '(a)','# H(x+a) = 1-(1+xi*x/b)**(-1/xi) with'
            print '(a,f16.3,a,f16.3,a,f16.3)','# a = ',a,' \\pm ',a975
     +           -a25
            print '(a,f16.3,a,f16.3,a,f16.3)','# b = ',b,' \\pm ',b975
     +           -b25
            print '(a,f16.3,a,f16.3,a,f16.3)','# xi  = ',xi,' \\pm ',
     +           xi975-xi25
            print '(a,f16.3,a,f16.3,a,f16.3)','# alpha ',alpha,' \\pm ',
     +           alpha975-alpha25
        end if
        call printcovreturnvalue(ntype,t,t25,t975,yr1a,yr2a,lweb)
        call printcovreturntime(year,xyear,tx,tx25,tx975,yr1a,yr2a,lweb)
!       plot fit for present-day climate
        call plotreturnvalue(ntype,t25(1,2),t975(1,2),j2-j1+1)

        if ( plot ) then
            call plot_tx_cdfs(txtx,nmc,ntype)
        end if

        if ( assume.eq.'both' ) then
            write(0,*) 'fitgevcov: error: cannot handle plotting yet '
     +           //'for assume = both'
            write(*,*) 'fitgevcov: error: cannot handle plotting yet '
     +           //'for assume = both'
            stop
        end if
        ! compute distribution at year and plot it
        if ( assume.eq.'shift' ) then
            if ( lchangesign ) then
                do i=1,ncur
                    yy(i) = yy(i) + alpha*(zz(i)-cov2)
                end do
            else
                do i=1,ncur
                    !!!print *,'yy(',i,') was ',yy(i)
                    yy(i) = yy(i) - alpha*(zz(i)-cov2)
                    !!!print *,'yy(',i,')  is ',yy(i)
                end do
            end if
        else if ( assume.eq.'scale' ) then
            if ( lchangesign ) then
                do i=1,ncur
                    yy(i) = yy(i)*exp(-alpha*(zz(i)-cov2))
                end do
            else
                do i=1,ncur
                    yy(i) = yy(i)*exp(alpha*(zz(i)-cov2))
                end do
            end if
        end if
        ys(1:ncur) = yy(1:ncur)
        ! no cuts
        minindx = -2e33
        snorm = 1
        ! GPD fit
        nfit = 6
        call plot_ordered_points(yy,ys,yrs,ncur,ntype,nfit,
     +       a+cov2*alpha,b,xi,j1,j2,minindx,a,threshold,
     +       year,xyear,snorm,lchangesign,lwrite)
        ! and print xyear if the distribution would be at yr1a
        print '(a)'
        print '(a)'
        f = 1 - 1/real(ntot+1)*0.9**100
        call printpoint(0,1/real(ntot+1),ntype,-999.9,
     +       xyear+alpha*(cov2-cov1),100*yr1a)
        call printpoint(0,f,ntype,-999.9,
     +       xyear+alpha*(cov2-cov1),100*yr1a)

        end
*  #] fitgpdcov:
*  #[ fit1gpdcov:
        subroutine fit1gpdcov(a,b,xi,alpha,dalpha,iter)
        implicit none
        integer iter
        real a,b,xi,alpha,dalpha
        integer i
        real q(4),p(4,3),y(4),tol
        real llgpdcov
        external llgpdcov
        integer nthreshold
        real athreshold,pthreshold
        common /fitdata5/ nthreshold,athreshold,pthreshold
*
        q(1) = b
        q(2) = xi
        q(3) = alpha
        q(4) = 3e33
        p(1,1) = q(1) *0.9
        p(1,2) = q(2) *0.9
        p(1,3) = q(3) - dalpha
        p(2,1) = p(1,1) *1.2
        p(2,2) = p(1,2)
        p(2,3) = p(1,3)
        p(3,1) = p(1,1)
        p(3,2) = p(1,2) *1.2 + 0.1
        p(3,3) = p(1,3)
        p(4,1) = p(1,1)
        p(4,2) = p(1,2)
        p(4,3) = p(1,3) + 2*dalpha
        do i=1,4
            q(1) = p(i,1)
            q(2) = p(i,2)
            q(3) = p(i,3)
            y(i) = llgpdcov(q)
        enddo
        tol = 1e-4
        call amoeba(p,y,4,3,3,tol,llgpdcov,iter)
*       maybe add restart later
        a = athreshold
        b = p(1,1)
        xi = p(1,2)
        alpha = p(1,3)
        end
*  #] fit1gpdcov:
*  #[ fit2gpdcov:
        subroutine fit2gpdcov(a,b,xi,alpha,beta,dalpha,dbeta,iter)
        implicit none
        integer iter
        real a,b,xi,alpha,beta,dalpha,dbeta
        integer i
        real q(4),p(5,4),y(5),tol
        real llgpdcov
        external llgpdcov
        integer nthreshold
        real athreshold,pthreshold
        common /fitdata5/ nthreshold,athreshold,pthreshold
*
        q(1) = b
        q(2) = xi
        q(3) = alpha
        q(4) = beta
        p(1,1) = q(1) *0.9
        p(1,2) = q(2) *0.9
        p(1,3) = q(3) - dalpha
        p(1,4) = q(4) - dbeta
        p(2,1) = p(1,1) *1.2
        p(2,2) = p(1,2)
        p(2,3) = p(1,3)
        p(2,4) = p(1,4)
        p(3,1) = p(1,1)
        p(3,2) = p(1,2) *1.2 + 0.1
        p(3,3) = p(1,3)
        p(3,4) = p(1,4)
        p(4,1) = p(1,1)
        p(4,2) = p(1,2)
        p(4,3) = p(1,3) + 2*dalpha
        p(4,4) = p(1,4)
        p(5,1) = p(1,1)
        p(5,2) = p(1,2)
        p(5,3) = p(1,3)
        p(5,4) = p(1,4) + 2*dbeta
        do i=1,5
            q(1) = p(i,1)
            q(2) = p(i,2)
            q(3) = p(i,3)
            q(4) = p(i,4)
            y(i) = llgpdcov(q)
        enddo
        tol = 1e-4
        call amoeba(p,y,5,4,4,tol,llgpdcov,iter)
*       maybe add restart later
        a = athreshold
        b = p(1,1)
        xi = p(1,2)
        alpha = p(1,3)
        beta = p(1,4)
        end
*  #] fit2gpdcov:
*  #[ llgpdcov:
        real function llgpdcov(p)
*
*       computes the log-likelihood function for a covariant-dependent GPD distribution
*       with parameters a,b,xi,alpha=p(1-4) and data in common.
*
        implicit none
        integer maxloop
        parameter(maxloop=10)
*       
        real p(4)
*
        integer i,n,nold,iloop
        real x,z,xi,s,aold,dadn,aa,bb
        save dadn
        real,allocatable :: xx(:)
*
        integer nmax,ncur
        parameter(nmax=100000)
        real data(2,nmax),restrain
        logical llwrite
        common /fitdata3/ data
        common /fitdata2/ restrain,ncur,llwrite
        character cassume*5
        common /fitdata4/ cassume
        integer nthreshold
        real athreshold,pthreshold
        common /fitdata5/ nthreshold,athreshold,pthreshold
*
        data dadn /3e33/
*
        llgpdcov = 0
        allocate(xx(ncur))
        if ( abs(p(2)).gt.10 ) then
            llgpdcov = 3e33
            goto 999
        endif
        if ( restrain.lt.0 ) then
            write(0,*) 'llgpdcov: restrain<0 ',restrain
            call abort
        end if
!
!       get threshold
!
        if ( cassume.ne.'scale' ) then
            do i=1,ncur
                xx(i) = data(1,i) - p(3)*data(2,i)
            end do
            call nrsort(ncur,xx)
            athreshold = (xx(ncur-nthreshold) + xx(ncur-nthreshold+1))/2
            xx = xx - athreshold
        else
            ! iterative procedure I am afraid...
            ! assume athreshold has been set to a reasonable value higher up
            do iloop=1,maxloop
                n = 0
                nold = -1
                aold = 3e33
                do i=1,ncur
                    xx(i) = data(1,i) - athreshold*exp(p(3)*data(2,i))
                    if ( xx(i).gt.0 ) then
                        n = n + 1
                    end if
                end do
                if ( n.eq.nthreshold ) then
                    exit
                end if
                if ( dadn.gt.1e33 ) then
                    athreshold = athreshold + (n-nthreshold)*abs(p(2))
                else
                    athreshold = athreshold + (n-nthreshold)*dadn
                end if
                if ( nold.gt.0 ) then
                    dadn = (athreshold-aold)/(n-nold)
                end if
                nold = n
                aold = athreshold
                if ( llwrite ) print *,iloop,n,nthreshold,athreshold
            end do
            if ( iloop.gt.maxloop ) then
                write(*,*) 'llgpdcov: warning: threshold computation '//
     +               'did not converge ',iloop,n,nthreshold,athreshold
            end if
            call nrsort(ncur,xx)
        end if
!
!       and compute cost function
!
        do i=ncur-nthreshold+1,ncur
            call getabfromcov(athreshold,p(1),p(3),p(4),data(2,i),aa,bb)
            if ( abs(p(2)).lt.1e-30 ) then
                llgpdcov = 3e33
                goto 999
            end if
            z = xx(i)
            if ( z.lt.0 ) then
                write(0,*) 'llgpdcov: error: z<0 ',z,i,ncur
                call abort
            endif
            if ( 1+xi*z/bb.le.0 ) then
                llgpdcov = 3e33
                goto 999
            endif
            if ( abs(xi).lt.1e-4 ) then
                llgpdcov = llgpdcov - z/bb + (z/bb)**2*xi/2
***                print *,i,z, - z/b + (z/b)**2*xi/2 - log(b)
            else
                llgpdcov = llgpdcov - (1+1/xi)*log(1+xi*z/bb)
***                print *,i,z, - (1+1/xi)*log(1+xi*z/b) - log(b)
            endif
            llgpdcov = llgpdcov - log(bb)
        enddo
*       normalization is not 1 in case of cut-offs
        call gpdcovnorm(athreshold,abs(p(1)),p(2),p(3),p(4),s)
        if ( s.lt.1e33 ) then
            llgpdcov = llgpdcov - ncur*log(s)
        else
            llgpdcov = 3e33
            goto 999
        end if
        if ( restrain.ne.0 ) then
*           preconditioning on xi with gaussian of width restrain/2
*           around 0
            llgpdcov = llgpdcov - (xi/(restrain/2))**2/2
        endif
*       minimum, not maximum
        llgpdcov = -llgpdcov
*
  999   continue
        deallocate(xx)
        if ( llwrite ) print *,'a,b,xi,alpha,llgpdcov = ',
     +       athreshold,p(1),p(2),p(3),llgpdcov
        end
*  #] llgpdcov:
*  #[ gpdcovnorm:
        subroutine gpdcovnorm(a,b,xi,alpha,beta,s)
        implicit none
	include "getopts.inc"
        real a,b,xi,alpha,beta,s
        real z1,z2

        if ( minindx.gt.-1e33 .or. maxindx.lt.1e33 ) then
            write(0,*) 'gpdcovnorm: boundaries not yet avaiable for '//
     +           'fit of GPD(t)'
            call abort
        else
            s = 1
        endif
***        print *,'gpdcovnorm: norm = ',a,b,s
        end
*  #] gpdcovnorm:
*  #[ gpdcovreturnlevel:
        real function gpdcovreturnlevel(a,b,xi,alpha,beta,x,cov)
!
!       compute return times given the GPD distribution parameters a,b,xi and 
!       x = log10(returntime) for covariant cov and fit parameter alpha
!       Uses a few Taylor series approximation for xi small and/or return time large
!
        implicit none
        real a,b,xi,alpha,beta,x,cov
        real aa,bb,y,t
        integer nthreshold
        real athreshold,pthreshold
        common /fitdata5/ nthreshold,athreshold,pthreshold

        call getabfromcov(a,b,alpha,beta,cov,aa,bb)
        x = x + log10(1-pthreshold/100)
        if ( abs(xi).gt.10 ) then
            gpdcovreturnlevel = 3e33
        else if ( abs(xi).lt.1e-4 ) then
            t = bb*x*log(10.) + 0.5*xi*(x*log(10.))**2
        else
            y = xi*x*log(10.)
            if ( y.lt.46 ) then
                t = bb/xi*(-1 + exp(y))
            else
                t = 1e20
            end if
        end if
        t = t + aa ! threshold
        gpdcovreturnlevel = t
        end
*  #] gpdcovreturnlevel:
*  #[ gpdcovreturnyear:
        real function gpdcovreturnyear(a,b,xi,alpha,beta,xyear,cov)
!
!       compute the return time of the value xyear with the fitted values
!
        implicit none
        real a,b,xi,alpha,beta,xyear,cov
        integer i,n,ntot
        real x,y,z,tx,aa,bb
        integer nmax,ncur
        parameter(nmax=100000)
        real data(2,nmax),restrain
        logical llwrite
        common /fitdata3/ data
        common /fitdata2/ restrain,ncur,llwrite
        character cassume*5
        common /fitdata4/ cassume
        integer nthreshold
        real athreshold,pthreshold
        common /fitdata5/ nthreshold,athreshold,pthreshold

        x = xyear
        call getabfromcov(a,b,alpha,beta,cov,aa,bb)
        if ( xyear.gt.aa ) then
            x = xyear - aa
            z = (1 + xi*x/bb)
            if ( z.gt.0 .and. abs(xi).gt.1e-3 ) then
                tx = z**(1/xi)/(1-pthreshold/100)
            else if ( z.gt.0 ) then
                tx = exp(z - 0.5*xi*z**2)/(1-pthreshold/100)
            else
                tx = 1e20
            end if
            if ( tx.gt.1e20 ) then
                write(0,*) 'fitgpd: tx > 1e20: ',tx
                write(0,*) 'z,xi = ',z,xi
            end if
        else
            n = 0
            if ( cassume.eq.'shift' ) then
                do i=1,ncur
                    if ( data(1,i) - alpha*(data(2,i)-cov)
     +                   .gt.xyear ) n = n + 1
                enddo
            else if ( cassume.eq.'scale' ) then
                do i=1,ncur
                    if ( data(1,i)*exp(alpha*(data(2,i)-cov))
     +                   .gt.xyear ) n = n + 1
                enddo
            else if ( cassume.eq.'both' ) then
                do i=1,ncur
                    ! not sure whether this is correct
                    if ( (data(1,i)-xyear - alpha*(data(2,i)-cov))
     +                   .gt.0 ) n = n + 1 
                enddo
            else
                write(0,*) 'gpdcovreturnyear: error: unknown value '//
     +               'for assume: ',cassume
                call abort
            end if
            ! approximately... I do not have this information here.
            ntot = nint(nthreshold/(1-pthreshold/100))
            tx = real(ntot+1)/real(n)
        endif
        if ( .false. .and. tx.gt.1e20 ) then
            write(0,*) 'gpdcovreturnyear: tx > 1e20: ',tx
            write(0,*) 'a,b,xi,alpha,xyear = ',a,b,alpha,xi,xyear
        endif
        gpdcovreturnyear = tx
        end
*  #] gpdcovreturnyear:
