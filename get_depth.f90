program get_depth

!       compute the depth of the x-degree isotherm or thermocline
!       or mixed layer from 3D ocean data

    implicit none
    include 'params_s.h'
    include 'netcdf.inc'
    logical :: lwrite,ensemble
    integer :: nens1,nens2
    common /options/ lwrite,ensemble,nens1,nens2
    integer,parameter :: nyrmax=60,nlevmax=3,mensmax=1
    integer :: n,nx,ny,nz,nt,firstyr,lastyr,firstmo,nvars, &
        ivars(2,nvmax),jvars(6,nvmax),ncid,endian, &
        status,nperyear,mens
    logical :: lexist
    real :: xx(nxmax),yy(nymax),zz(nzmax),undef, &
        field(nxmax,nymax,12,nyrmax), &
        res(nxmax,nymax,12,nyrmax)
    character :: infile*255,datfile*255,outfile*255,line*255 &
        ,vars(nvmax)*10,lvars(nvmax)*40,title*255,units(nvmax)*10

!   process command line

    lwrite = .false. 
    n = command_argument_count()
    if ( n < 2 ) then
        write(0,*) 'usage: get_{depth|heat|thermocline|mld}'// &
            'infile.[ctl|nc] {temp|heat|delta_t} outfile.[ctl|nc]'
        call exit(-1)
    end if
    call get_command_argument(1,infile)
    if ( index(infile,'%') > 0 .or. index(infile,'++') > 0 ) then
        ensemble = .true. 
        call filloutens(infile,0)
    else
        mens = 0
    end if
    if ( lwrite ) print *,'get_depth: nf_opening file ',trim(infile)
    status = nf_open(infile,nf_nowrite,ncid)
    if ( status /= nf_noerr ) then
        call parsectl(infile,datfile,nxmax,nx,xx,nymax,ny,yy,nzmax &
            ,nz,zz,nt,nperyear,firstyr,firstmo,undef,endian,title &
            ,1,nvars,vars,ivars,lvars,units)
        ncid = -1
        if ( ensemble ) then
            do mens=1,nensmax
                call get_command_argument(1,line)
                call filloutens(line,mens)
                inquire(file=line,exist=lexist)
                if ( .not. lexist ) go to 100
            end do
        100 continue
            mens = mens - 1
            write(0,*) 'located ',mens+1,' ensemble members<br>'
        end if
    else
        call parsenc(infile,ncid,nxmax,nx,xx,nymax,ny,yy,nzmax &
            ,nz,zz,nt,nperyear,firstyr,firstmo,undef,title,1,nvars &
            ,vars,jvars,lvars,units)
        if ( ensemble ) then
            do mens=1,nensmax
                call get_command_argument(1,line)
                call filloutens(line,mens)
                status = nf_open(line,nf_nowrite,ncid)
                if ( status /= nf_noerr ) go to 200
            end do
        200 continue
            mens = mens - 1
            write(0,*) 'located ',mens+1,' ensemble members<br>'
        end if
    end if
    lastyr = firstyr + (firstmo+nt-2)/nperyear
!   process arguments
    if ( ensemble ) write(0,*) 'Using ensemble members ',nens1,' to ',nens2,'<br>'
    call get_command_argument(1,infile)

!   check dimensions

    if ( nx*ny*nz*nperyear*(lastyr-firstyr+1) > nxmax*nymax*12*nyrmax ) then
        write(0,*) 'get_deoth: error: field too large '
        write(0,*) '  nx       = ',nx
        write(0,*) '  ny       = ',ny
        write(0,*) '  nz       = ',nz
        write(0,*) '  nperyear = ',nperyear
        write(0,*) '  years    = ',firstyr,lastyr
        write(0,*) 'total request',nx*ny*nz*nperyear*(lastyr-firstyr+1)
        write(0,*) 'available    ',nxmax*nymax*12*nyrmax
        write(*,*) 'get_depth: error: field too large '
        write(*,*) '  nx       = ',nx
        write(*,*) '  ny       = ',ny
        write(*,*) '  nz       = ',nz
        write(*,*) '  nperyear = ',nperyear
        write(*,*) '  years    = ',firstyr,lastyr
        write(*,*) 'total request',nx*ny*nz*nperyear*(lastyr-firstyr+1)
        write(*,*) 'available    ',nxmax*nymax*12*nyrmax
        call exit(-1)
    end if
    if ( nx*ny*nz > nxmax*nymax*nlevmax ) then
        write(0,*) 'get_depth: error: fields too large: '
        write(0,*) 'nx,ny,nz            = ',nx,ny,nz,nx*ny*nz
        write(0,*) 'nxmax,nymax,nlevmax = ',nxmax,nymax,nlevmax,nxmax*nymax*nlevmax
        write(*,*) 'get_depth: error: fields too large: '
        write(*,*) 'nx,ny,nz            = ',nx,ny,nz,nx*ny*nz
        write(*,*) 'nxmax,nymax,nlevmax = ',nxmax,nymax,nlevmax,nxmax*nymax*nlevmax
        call exit(-1)
    end if

!   to save on RAM usage, too lazy to replace by allocate arrays...

    call gfield(datfile,ncid,field,res,nx,xx,ny,yy,nz,zz,nt &
        ,nperyear,firstyr,lastyr,firstmo,undef,endian,jvars)
end program get_depth

subroutine gfield(datfile,ncid,field,res,nx,xx,ny,yy,nz,zz,nt &
    ,nperyear,firstyr,lastyr,firstmo,undef,endian,jvars)

!   break to use field() compactly

    implicit none
    include 'params.h'
    integer,parameter :: recfac=4
    logical :: lwrite,ensemble
    integer :: nens1,nens2
    common /options/ lwrite,ensemble,nens1,nens2
    real,parameter :: absent=3e33

    integer :: ncid,endian,nx,ny,nz,nt,nperyear,firstyr,lastyr, &
        firstmo,jvars(6,nvmax)
    real :: field(nx,ny,nz,nperyear,firstyr:lastyr), &
        res(nx,ny,nperyear,firstyr:lastyr), &
        undef,xx(nx),yy(ny),zz(nz)
    character datfile*(*)

    integer :: jx,jy,jz,jz0,i,j,k,k1,k2,n,mo,yr,itype,ldir, &
        nvars,ivars(2,nvmax),iens
    real :: val,depth(nzmax),gradients(nzmax),gradmax,temp,tmin,tmax,dt &
        ,grad,z
    logical :: lexist
    character :: outfile*255,line*255,yesno*1,dir*255,string*10 &
        ,vars(nvmax)*10,lvars(nvmax)*40,units(nvmax)*20,title*255
    integer :: rindex

    if ( nz <= 4 ) then
        write(0,*) 'error: cannot get depth properties with nz = ',nz
        write(*,*) 'error: cannot get depth properties with nz = ',nz
        call exit(-1)
    end if
    call get_command_argument(0,line)
    if ( index(line,'get_depth') /= 0 ) then
        itype = 1
    else if ( index(line,'get_heat') /= 0 ) then
        itype = 2
    else if ( index(line,'get_therm') /= 0 ) then
        itype = 0
    else if ( index(line,'get_mld') /= 0 ) then
        itype = 3
    else
        goto 901
    end if
    if ( itype > 0 ) then
        call get_command_argument(2,line)
        read(line,*,err=902) val
    end if

!   read field, change absent values to our convention

    if ( ensemble ) then
    !           put the %% back in datfile...
        if ( nens2 < 10 ) then
            i = 1
        else if ( nens2 < 100 ) then
            i = 2
        else if ( nens2 < 1000 ) then
            i = 3
        else
            write(0,*) 'get_depth: cannot handle ensembles up to ',nens2,' yet'
            call exit(-1)
        end if
        string = '0000000'
        j = rindex(datfile,string(1:i))
        if ( j == 0 ) then
            write(0,*) 'get_depth: error: cannot find ' &
            ,string(1:i),' in ',trim(datfile)
            call exit(-1)
        end if
        do k=j,j+i-1
            datfile(k:k) = '%'
        end do
    end if
    do iens=nens1,nens2
        call keepalive(iens-nens1+1,nens2-nens1+1)
        if ( ncid == -1 ) then
            dir=datfile
            if ( ensemble ) call filloutens(dir,iens)
            print *,'looking for '//trim(dir)
            inquire(file=dir,exist=lexist)
            if ( .not. lexist ) then
                print *,'looking for '//trim(dir)//'.gz'
                inquire(file=trim(dir)//'.gz',exist=lexist)
                if ( .not. lexist ) then
                    nens2 = iens-1
                    if ( nens2 >= nens1 ) then
                        write(0,*) 'Found ensemble 0 to ',nens2,'<br>'
                        goto 5
                    else
                        write(0,*) 'Cannot locate file ',trim(dir)
                        call exit(-1)
                    end if
                end if
            end if
            if ( lwrite ) then
                print *,'opening file ',trim(dir)
            end if
            call zreaddatfile(dir,field(1,1,1,1,firstyr), &
                nx,ny,nz,nx,ny,nz,nperyear,firstyr,lastyr, &
                firstyr,firstmo,nt,undef,endian,lwrite,firstyr &
                ,lastyr,1,1)
        else
            if ( nz /= 1 ) then
                write(0,*) 'cannot read 3D netCDF files yet'
                call exit(-1)
            end if
            if ( ensemble ) then
                write(0,*) 'cannot handle ensembles of netcdf files yet'
                call exit(-1)
            end if
            call readncfile(ncid,field,nx,ny,nx,ny,nperyear,firstyr &
                ,lastyr,firstyr,firstmo,nt,undef,lwrite,firstyr &
                ,lastyr,jvars)
        end if
    5   continue

!       open output file
    
        call get_command_argument(iargc(),outfile)
        if ( ensemble ) call filloutens(outfile,iens)
        inquire(file=outfile,exist=lexist)
        if ( lexist ) then
            print *,'output file ',outfile(1:index(outfile,' ')-1), &
                ' already exists, overwrite? [y/n]'
            read(*,'(a)') yesno
            if (  yesno /= 'y' .and. yesno /= 'Y' .and. &
            yesno /= 'j' .and. yesno /= 'J' ) then
                call exit(-1)
            end if
            open(2,file=outfile)
            close(2,status='delete')
        end if
        if ( index(outfile,'.nc') /= 0 ) then
            print *,'netCDF output not yet ready'
            call exit(-1)
        else
            i = index(outfile,'.ctl')
            if ( i /= 0 ) then
                datfile = outfile(:i-1)//'.dat'
            else
                datfile = outfile
            end if
            open(unit=2,file=datfile,form='unformatted',access &
                ='direct',recl=recfac*nx*ny,err=920)
        end if
    
    !           loop over time, gridpoints
    
        yr = firstyr
        mo = firstmo - 1
        do i=1,nt
            call keepalive(i,nt)
            mo = mo + 1
            if ( mo > nperyear ) then
                mo = mo - nperyear
                yr = yr + 1
            end if
            do jy=1,ny
                do jx=1,nx
                    if ( itype == 0 ) then
!                       find thermocline - steepest gradient
                        tmin = 0
                        tmax = 1000
                        dt = 50
                        n = 1
                        grad = -1
                        do jz=1,nz-1
                            if ( field(jx,jy,jz,mo,yr) < 1e33 ) then
                                do k=jz+1,nz
                                    if ( field(jx,jy,k,mo,yr) < 1e33 ) then
                                        gradients(n) = (field(jx,jy,jz,mo,yr) &
                                            - field(jx,jy,k,mo,yr))/(zz(k) - zz(jz))
                                        if ( abs(gradients(n)-grad) > 0.01 ) then
                                            grad = gradients(n)
                                            depth(n) = (zz(jz) + zz(k))/2
                                            n = n + 1
                                            jz0 = jz
                                        else
                                            depth(n-1) = (zz(jz0) + zz(k))/2
                                        end if
                                        goto 110
                                    end if
                                end do
                            110 continue
                            end if
                        end do
                        n = n-1
                        if ( n > 2 ) then
                            call maxquad(res(jx,jy,mo,yr),gradmax,depth,gradients,n)
                            if ( res(jx,jy,mo,yr) < 1e33 ) then
                                z = res(jx,jy,mo,yr)
                                do jz=1,n-1
                                    if ( (zz(jz)-z)*(zz(jz+1)-z) < 0 ) then
                                        do k1=jz,1,-1
                                            if ( field(jx,jy,k1,mo,yr) < 1e33 ) goto 120
                                        end do
                                        goto 190
                                    120 continue
                                        do k2=jz+1,nz
                                            if ( field(jx,jy,k2,mo,yr) < 1e33 ) &
                                            goto 130
                                        end do
                                        goto 190
                                    130 continue
                                        temp = ( field(jx,jy,k1,mo,yr)*(zz(k2)-z) + &
                                            field(jx,jy,k2,mo,yr)*(z-zz(k1)))/(zz(k2)-zz(k1))
                                        if ( temp < 15 .or. temp > 27 ) then
                                            print *,'weird thermocline at ',xx(jx) &
                                                ,yy(jy),jz,jz+1,mo,yr,z,temp,field(jx &
                                                ,jy,k1,mo,yr),k1,field(jx,jy,k2,mo,yr),k2
                                            do k=1,n
                                                print *,k,depth(k),gradients(k)
                                            end do
                                        end if
                                        goto 190
                                    end if
                                end do
                            190 continue
                            end if
                        else
                            res(jx,jy,mo,yr) = 3e33
                        end if
                    else if ( itype == 1 ) then
!                       find val-degree isotherm
                        tmin=0
                        tmax=6000
                        dt = 10
                        res(jx,jy,mo,yr) = 3e33
                        do jz=1,nz-1
                            if ( field(jx,jy,jz,mo,yr) < 1e33 .and. &
                                 field(jx,jy,jz+1,mo,yr) < 1e33 ) then
                                if ( (field(jx,jy,jz,mo,yr)-val)* &
                                     (field(jx,jy,jz+1,mo,yr)-val) <= 0 ) then
                                    res(jx,jy,mo,yr) = ((field(jx,jy,jz,mo,yr)-val)*zz(jz+1) + &
                                        (val-field(jx,jy,jz+1,mo,yr))*zz(jz))/ &
                                        (field(jx,jy,jz,mo,yr) - field(jx,jy,jz+1,mo,yr))
                                end if
                            end if
                        end do
                    else if ( itype == 2 ) then
!                       find heat content of top val meters
                        tmin=val*3
                        tmax=val*30
                        dt = 50
                        res(jx,jy,mo,yr) = 0
                        do jz=2,nz-1
                            if ( field(jx,jy,jz,mo,yr) < 1e33 .and. &
                                 res(jx,jy,mo,yr) <= 1e33 .and. &
                            zz(jz) < val ) then
                                if ( jz == 1 ) then
                                    res(jx,jy,mo,yr) = field(jx,jy,jz,mo,yr)*(zz(1)+zz(2))/2
                                else
                                    res(jx,jy,mo,yr) = res(jx,jy,mo,yr) + &
                                        field(jx,jy,jz,mo,yr)*(zz(jz+1)-zz(jz-1))/2
                                end if
                            else if ( zz(jz) < val ) then
                                res(jx,jy,mo,yr) = 3e33
                            end if
                        end do
                    else if ( itype == 3 ) then
                        tmin=0
                        tmax=5000
                        dt = 10
!                       find mixed layer depth with a val-degree criterium
                        res(jx,jy,mo,yr) = 3e33
                        if ( field(jx,jy,1,mo,yr) < 1e33 ) then
                            temp = field(jx,jy,1,mo,yr) - val
                            do jz=1,nz-1
                                if ( field(jx,jy,jz,mo,yr) < 1e33  .and. &
                                     field(jx,jy,jz+1,mo,yr) < 1e33 ) then
                                    if ( (field(jx,jy,jz,mo,yr)-temp)* &
                                         (field(jx,jy,jz+1,mo,yr)-temp) <= 0 ) then
                                        res(jx,jy,mo,yr) = ((field(jx,jy,jz,mo,yr)-temp)* &
                                            zz(jz+1) + (temp-field(jx,jy,jz+1,mo,yr))* &
                                            zz(jz))/(field(jx,jy,jz,mo,yr)-field(jx,jy,jz+1,mo,yr))
                                    end if
                                end if
                            end do
                        end if
                        if ( res(jx,jy,mo,yr) <= 0 ) then
                            print *,'error: mld(',xx(jx),yy(jy),mo,yr,') = ',res(jx,jy,mo,yr)
                            do jz=1,nz
                                if ( field(jx,jy,jz,mo,yr) < 1e33 ) then
                                    print *,jz,field(jx,jy,jz,mo,yr)
                                end if
                            end do
                        end if
                    else
                        write(0,*) 'error: unknown itype ',itype
                        call exit(-1)
                    end if
                    if ( lwrite ) then
                        if ( res(jx,jy,mo,yr) < 1e33 ) then
                            print *,'res(',jx,jy,mo,yr,') = ',res(jx,jy,mo,yr)
                        end if
                    end if
                end do       ! nx
            end do           ! ny
            call latlonint(res(1,1,mo,yr),1,1,ny,nx,yy,xx,1,tmin,tmax,dt)
            call latlonint(res(1,1,mo,yr),1,1,ny,nx,yy,xx,1,tmin,tmax,dt)
        end do               ! nt
    
!       write output field in GrADS format
    
        print *,'writing output'
        yr = firstyr
        mo = firstmo - 1
        do i=1,nt
            call keepalive(i,nt)
            mo = mo + 1
            if ( mo > nperyear ) then
                mo = mo - nperyear
                yr = yr + 1
            end if
            write(2,rec=i) ((res(jx,jy,mo,yr),jx=1,nx),jy=1,ny)
        end do
        close(2)
        if ( index(outfile,'.ctl') /= 0 ) then
            call getenv('DIR',dir)
            ldir = len_trim(dir)
            if ( ldir == 0 ) ldir=1
            if ( dir(ldir:ldir) /= '/' ) then
                ldir = ldir + 1
                dir(ldir:ldir) = '/'
            end if
            title = ' '
            n = 1
            do i=0,iargc()-1
                call get_command_argument(i,line)
                if ( line(1:ldir) == dir(1:ldir) ) then
                    title(n:) = line(ldir+1:)
                else
                    title(n:) = line
                end if
                n = len_trim(title) + 2
            end do
            nvars = 1
            if ( itype == 0 ) then
                vars(1) = 'zth'
                lvars(1) = 'thermocline depth [m]'
            else if ( itype == 1 ) then
                if ( abs(val-real(nint(val))) < 0.01 ) then
                    write(vars(1),'(a,i2.2)') 'z',nint(val)
                    write(lvars(1),'(f4.0,a)') val,'-degree isotherm [m]'
                else if ( abs(10*val-real(nint(10*val))) < 0.01 ) then
                    write(vars(1),'(a,i3.3)') 'z',nint(10*val)
                    write(lvars(1),'(f5.1,a)') val,'-degree isotherm [m]'
                else
                    write(vars(1),'(a,i3.3)') 'z',nint(100*val)
                    write(lvars(1),'(f8.3,a)') val,'-degree isotherm [m]'
                end if
            else if ( itype == 2 ) then
                vars(1) = 'heat'
                write(lvars(1),'(a,i5,a)') 'heat contenty of the top ',nint(val),' meter [Cm]'
            else if ( itype == 3 ) then
                vars(1) = 'mld'
                write(lvars(1),'(a,f5.2,a)') 'mixes layer depth (dT=',val,'C) [m]'
            else
                write(0,*) 'get_depth: error: itype = ',itype
                call exit(-1)
            end if
            ivars(1,1) = 0
            ivars(2,1) = 99
            call writectl(outfile,datfile,nx,xx,ny,yy,1,zz &
                ,nt,nperyear,firstyr,firstmo,absent,title,nvars &
                ,vars,ivars,lvars,units)
        end if
    end do

!   error messages

    goto 999
901 print *,line,' not known'
    call exit(-1)
902 print *,'get_depth: error reading val from ',trim(line)
    call exit(-1)
903 print *,'error reading date from file ',trim(line),' at record ',k
    call exit(-1)
904 print *,'error cannot locate field file file ',trim(line)
    call exit(-1)
920 print *,'error cannot open new file ',trim(datfile)
    call exit(-1)
999 continue
end subroutine gfield

subroutine latlonint(temp,nt,ntimes,nlat,nlon,lats,lons,iiwrite,tmin,tmax,dt)

!       interpolate latitude and longitude
!       latitude: if there is a measurement within maxlat degree
!       longitude: if there is a measurement within maxlon degrees
!       or if the temperature difference is less than dt.

    implicit none
    integer :: ntimes,nt,nlat,nlon,iiwrite
    real :: lats(nlat),lons(nlon)
    real :: temp(nlon,nlat,nt),tmin,tmax,dt
    real :: maxtemp
    integer :: i,j,k,l,n,statelat,statelon,lastlat,nextlat &
        ,lastlon,nextlon,ii(2),jj(2),i1,j1,iwrite,iwritesav
    character :: idigit*1
    integer :: maxlat,maxlon
    logical :: again
    data maxlat,maxlon /2,10/

!   init

    iwrite = iiwrite        ! because we will change it
    if ( tmin /= 0 ) then
        i = log10(abs(tmin))
    else
        i = 0
    end if
    if ( tmin < 0 ) i = i + 1
    if ( tmax /= 0 ) then
        j = log10(abs(tmax))
    else
        j = 0
    end if
    write(idigit,'(i1)') 5+max(i,j)

!    loop over time, depths

    do k=1,ntimes
    
!       any valid values?
        n = 0
        do i=1,nlon
            do j=1,nlat
                if ( temp(i,j,k) < 1e33 ) then
                    n = n + 1
                    if ( n <= 2 ) then
                        ii(n) = i
                        jj(n) = j
                    end if
                end if
            end do
        end do
        if ( iwrite >= 2 ) print '(a,i8,a,i4,i3,a,i3)' &
            ,'latlonint: found ',n,' valid points at time ',k
!       only one point
        if ( n <= 1 ) goto 800
!	    adjacent points
        if ( n == 2 .and. &
            jj(1) == jj(2) .and. abs(ii(1)-ii(2)) == 1 .or. &
            ii(1) == ii(2) .and. abs(jj(1)-jj(2)) == 1 ) goto 800

!	    debug output
        if ( iwrite >= 2 ) then
            do j=nlat,1,-1
                print '(i4,100f'//idigit//'.2)',nint(lats(j)),(temp(i,j,k),i=1,nlon)
            end do
            print '(4x,100i'//idigit//')',(nint(lons(i)),i=1,nlon)
        end if
    
!	    there are more missing longitudes
        n = 0
        do j=1,nlat
!           to guard against errors
            lastlon = 1
            nextlon = nlon
            statelon = 0
            do i=1,nlon
!               to guard against errors
                lastlat = 1
                nextlat = nlat
!		        search for interval in longitude
                if ( temp(i,j,k) < 1e33 ) then
!			        valid point
                    statelon = 1
                    lastlon = i
                    nextlon = i
                    if ( iwrite >= 4 ) print *,'valid point'
                else if ( statelon == 0 ) then
!			        no interpolation possible
                    statelon = 0
                    if ( iwrite >= 4 ) print *,'no lon interpolation'
                else if ( statelon == 1 ) then
!			        invalid point, search for interval
                    do nextlon=i+1,nlon
                        if ( temp(nextlon,j,k) < 1e33 ) then
                            statelon = 2
                            if ( iwrite >= 4 ) print *,'lon interval ',lastlon,nextlon
                            goto 110
                        end if
                    end do
!                   to avoid errors later on
                    nextlon = nlon
                    statelon = 0
                    if ( iwrite >= 4 ) print *,'no lon interpolation'
                110 continue
                end if
                statelat = 0
                if ( statelon == 0 .or. statelon == 2 ) then
!       			search for interval in latitude
!			        (for each point in longitude anew)
                    do lastlat=j-1,1,-1
                        if ( temp(i,lastlat,k) < 1e33 ) then
!				            valid point
                            statelat = 1
                            if ( iwrite >= 4 ) print *,'found lastlat ',lastlat
                            goto 210
                        end if
                    end do
                    lastlat = nlat
                    statelat = 0
                    if ( iwrite >= 4 ) print *,'no lastlat'
                210 continue
                    if ( statelat /= 0 ) then
                        do nextlat=j+1,nlat,1
                            if ( temp(i,nextlat,k) < 1e33 ) then
!				                valid point
                                statelat = 2
                                if ( iwrite >= 4 ) print *,'found nextlat ',nextlat
                                goto 220
                            end if
                        end do
                        nextlat = nlat
                        statelat = 0
                        if ( iwrite >= 4 ) print *,'no nextlat'
                    220 continue
                    end if   ! found firstlat
                end if       ! invalid point

!		        interpolate!
            
                again = .false. 
            300 continue    ! comefrom: recomputation with debugging
                if ( statelon == 2 .and. ( &
                lons(i)-lons(lastlon) <= maxlon .or. &
                lons(nextlon)-lons(i) <= maxlon .or. &
                abs(temp(lastlon,j,k) - temp(nextlon,j,k)) <= dt )) then
                    if ( statelat == 2 .and. ( &
                        lats(j)-lats(lastlat) <= maxlat .or. &
                        lats(nextlat)-lats(j) <= maxlat .or. &
                        abs(temp(i,lastlat,k) - temp(i,nextlat,k)) <= dt ) ) then
                    
!			            interpolate both latitude and longitude
!                       weighted by maxlon:maxlat
                        n = n + 1
                        temp(i,j,k) = ( ( (lats(nextlat) - lats(j))*temp(i,lastlat,k) + &
                            (lats(j) - lats(lastlat))*temp(i,nextlat,k) )/maxlat + ( &
                            (lons(nextlon) - lons(i))*temp(lastlon,j,k) + &
                            (lons(i) - lons(lastlon))*temp(nextlon,j,k) )/maxlon )/( &
                            (lons(nextlon)-lons(lastlon))/real(maxlon) + &
                            (lats(nextlat)-lats(lastlat))/real(maxlat) )
                        if ( iwrite >= 3 ) then
                            print *,'latlonint: interpolating both ',i,j
                            print '(a,i3,i4,f8.2)', &
                                'last ',lastlat,nint(lats(lastlat)) &
                                ,temp(i,lastlat,k), &
                                ' new ',j,nint(lats(j)),temp(i,j,k) &
                                , &
                                'next ',nextlat,nint(lats(nextlat)) &
                                ,temp(i,nextlat,k), &
                                'last ',lastlon,nint(lons(lastlon)) &
                                ,temp(lastlon,j,k), &
                                ' new ',i,nint(lons(i)),temp(i,j,k) &
                                , &
                                'next ',nextlon,nint(lons(nextlon)) &
                                ,temp(nextlon,j,k)
                        end if
                    else    ! latitude interpolatable?
                    
!			            interpolate only longitude
                        n = n + 1
                        temp(i,j,k) = ((lons(nextlon) - lons(i))*temp(lastlon,j,k) + &
                            (lons(i) - lons(lastlon))*temp(nextlon,j,k) )/ &
                            (lons(nextlon)-lons(lastlon))
                        if ( iwrite >= 3 ) then
                            print *,'latlonint: interpolating longitude',i,j
                            print '(a,i3,i4,f8.2)', &
                                'last ',lastlon,nint(lons(lastlon)),temp(lastlon,j,k), &
                                ' new ',i,nint(lons(i)),temp(i,j,k), &
                                'next ',nextlon,nint(lons(nextlon)),temp(nextlon,j,k)
                        end if
                    end if   ! latitude interpolatable?
                else        ! longitude interplatable?
                    if ( statelat == 2 .and. ( &
                        lats(j)-lats(lastlat) <= maxlat .or. &
                        lats(nextlat)-lats(j) <= maxlat .or. &
                        abs(temp(i,lastlat,k) - temp(i,nextlat,k)) <= dt ) ) then

!                       interpolate only latitude
                        n = n + 1
                        temp(i,j,k) = ((lats(nextlat) - lats(j))*temp(i,lastlat,k) + &
                            (lats(j) - lats(lastlat))*temp(i,nextlat,k) )/(lats(nextlat)-lats(lastlat))
                        if ( iwrite >= 3 ) then
                            print *,'latlonint: interpolating latitude',i,j
                            print '(a,i3,i4,f8.2)', &
                                'last ',lastlat,nint(lats(lastlat)),temp(i,lastlat,k), &
                                ' new ',j,nint(lats(j)),temp(i,j,k), &
                                'next ',nextlat,nint(lats(nextlat)),temp(i,nextlat,k)
                        end if
                    end if   ! latitude interpolatable
                end if       ! longitude interpolatable
                if ( temp(i,j,k) /= 3e33 .and. ( &
                     temp(i,j,k) < tmin .or. &
                     temp(i,j,k) > tmax ) ) then
                    if ( again ) then
                        print *,'==========='
                        iwrite = iwritesav
                        again = .false. 
                    else    ! again?
                        print *,'latlonint: error: T=',temp(i,j,k),' recomputing with debugging'
                        iwritesav = iwrite
                        iwrite = 4
                        again = .true. 
                        goto 300
                    end if   ! again?
                end if       ! funny temperature
            end do           ! longitudes
        end do               ! latitudes
    
!	    debug output
        if ( n > 0 .and. iwrite >= 2 ) then
            do j=nlat,1,-1
                print '(i4,100f'//idigit//'.2)', &
                    nint(lats(j)),(temp(i,j,k),i=1,nlon)
            end do
            print '(4x,100i'//idigit//')',(nint(lons(i)),i=1,nlon)
        end if
    
!		comefrom: any valid values?
    800 continue
    end do                   ! loop over fields
end subroutine latlonint

