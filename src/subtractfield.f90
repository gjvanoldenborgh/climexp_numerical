program subtractfield

!   subtract a pattern times a series from field

    implicit none
    include 'params.h'
    include 'getopts.inc'
    integer,parameter :: nvarmax=15,recfa4=4
    integer :: i,j,yr,mo,yrp,yrq,mop,moq,jx,jy,jz,fyr,lyr,fyr2,lyr2 &
        ,mperyear,ivar,it,iens,ntvarid,irec
    integer :: mens,mens1,ncid,nx,ny,nz,nt,nperyear,firstyr,firstmo &
        ,endian,nvars,ivars(6,nvarmax)
    integer :: mens2,mens12,ncid2,nx2,ny2,nz2,nt2,nperyear2,firstyr2 &
        ,firstmo2,endian2,nvars2,ivars2(6,nvarmax),nmetadata1
    integer,allocatable :: itimeaxis(:)
    logical :: lexist
    real :: xx(nxmax),yy(nymax),zz(nzmax),undef
    real :: xx2(nxmax),yy2(nymax),zz2(nzmax),undef2
    real,allocatable :: field(:,:,:,:,:,:),pattern(:,:,:,:,:), series(:,:)
    character :: infile*1023,seriesfile*1023,patternfile*1023 &
        ,line*255,variable*40,outfile*255,file*255
    character :: datfile*1023,lz(3)*20,ltime*120,title*255 &
        ,history*20000,vars(1)*20,lvars(1)*100 &
        ,svars(1)*100,units(1)*60 &
        ,cell_methods(1)*100,metadata1(2,100)*2000
    character :: datfile2*1023,lz2(3)*20,ltime2*120,title2*255 &
        ,history2*20000,vars2(nvarmax)*60,lvars2(nvarmax)*100 &
        ,svars2(nvarmax)*100,units2(nvarmax)*60 &
        ,cell_methods2(nvarmax)*100,metadata2(2,100)*2000
    character :: var*60,unit*80,lvaR*80,svar*80,yesno
    integer,external :: leap

    lwrite = .false. 
    if ( command_argument_count() < 5 ) then
        print *,'usage: subtractfield field.[ctl|nc] '// &
            'pattern.[ctl|nc] variable series.dat outfile.nc '
        call exit(-1)
    endif
    call get_command_argument(1,infile)
    call get_command_argument(2,patternfile)
    call get_command_argument(3,variable)
    call get_command_argument(4,seriesfile)
    call get_command_argument(command_argument_count(),outfile)

!   read field

    call getmetadata(infile,mens1,mens,ncid,datfile,nxmax,nx &
        ,xx,nymax,ny,yy,nzmax,nz,zz,lz,nt,nperyear,firstyr,firstmo &
        ,ltime,undef,endian,title,history,1,nvars,vars,ivars &
        ,lvars,svars,units,cell_methods,metadata1,lwrite)

    call getopts(5,command_argument_count()-1,nperyear,yrbeg,yrend,.true.,mens1,mens)
    if ( lag1 /= 0 .or. lag2 /= 0 ) then
        write(0,*) 'subtractfiled: cannot handle lags yet'
        call exit(-1)
    end if

    fyr = firstyr
    lyr = firstyr + (nt+firstmo-1)/nperyear
    allocate(field(nx,ny,nz,nperyear,fyr:lyr,0:nens2))
    call readfield(ncid,infile,datfile,field,nx,ny,nz &
        ,nperyear,fyr,lyr,nens1,nens2,nx,ny,nz,nperyear,fyr,lyr &
        ,firstyr,firstmo,nt,undef,endian,vars,units,lstandardunits &
        ,lwrite)

!   read pattern

    call getmetadata(patternfile,mens12,mens2,ncid2,datfile2,nxmax &
        ,nx2,xx2,nymax,ny2,yy2,nzmax,nz2,zz2,lz2,nt2,nperyear2 &
        ,firstyr2,firstmo2,ltime2,undef2,endian2,title2,history2 &
        ,nvarmax,nvars2,vars2,ivars2,lvars2,svars2,units2 &
        ,cell_methods2,metadata2,lwrite)
    call checkgridequal3d(nx,ny,nz,xx,yy,zz,nx2,ny2,nz2,xx2,yy2,zz2)
    do ivar=1,nvars2
        if ( vars2(ivar) == variable ) then
            goto 100
        endif
    enddo
    write(0,*) 'patternfield: cannot locate ',trim(variable),' in pattern file ',trim(patternfile)
    write(0,*) 'I only have ',(vars2(ivar),ivar=1,nvars2)
    call exit(-1)
100 continue
    if ( ncid2 >= 0 ) then
!       make sure the variable is the first one in the jvar array
        if ( ivar > 1 ) then
            do i=1,5
                ivars2(i,1) = ivars2(i,ivar)
            enddo
            vars2(1) = vars2(ivar)
            lvars2(1) = lvars2(ivar)
        endif
    endif
    if ( lwrite ) print *,'located variable ',trim(variable),ivar
    fyr2 = firstyr2
    lyr2 = firstyr2 + (nt2+firstmo2-1)/nperyear
    allocate(pattern(nx2,ny2,nz2,nperyear,fyr2:lyr2))
    if ( ncid2 == -1 ) then
        call zreaddatfile(datfile2,pattern,nx2,ny2,nz2,nx2,ny2,nz2 &
            ,nperyear,fyr2,lyr2,firstyr2,firstmo2,nt2,undef2 &
            ,endian2,lwrite,fyr2,lyr2,ivar,nvars2)
    else
        call zreadncfile(ncid2,pattern,nx2,ny2,nz2,nx2,ny2,nz2 &
            ,nperyear,fyr2,lyr2,firstyr2,firstmo2,nt2,undef2,lwrite &
            ,fyr2,lyr2,ivars2)
    endif
    call merge_metadata(metadata1,nmetadata1,metadata2,title2,history2,'pattern_')

!   read series

    mperyear = nperyear
    allocate(series(mperyear,yrbeg:yrend))
    call readseriesmeta(seriesfile,series,mperyear,yrbeg,yrend,nperyear, &
        var,unit,lvar,svar,history2,metadata2,lstandardunits,lwrite)
    call add_varnames_metadata(var,lvar,svar,metadata2,'series')    
    call merge_metadata(metadata1,nmetadata1,metadata2,title2,history2,'series_')

!   the series has to be averaged over the same interval as in the
!   job that prodecued the regression file

    if ( lsum > 1 ) then
        if ( lwrite ) print *,'taking sum of series'
        if ( lsum > nperyear ) then
            write(0,*) 'subtractfield: cannot handle lsum > ', &
                'nperyear: ',lsum,nperyear
            call exit(-1)
        end if
        call sumit(series,mperyear,nperyear,yrbeg,yrend,lsum,oper)
    endif

!   compute (the easy part)

    do iens=nens1,nens2
        do yr=max(fyr,yr1),min(lyr,yr2)
            do mo=1,nperyear
                if ( firstyr2 == 0 .and. firstmo2 == nperyear .and. &
                nt2 == 1 ) then
                    yrp = 0
                    mop = 12
                    moq = mo
                    yrq = yr
                else if ( nt2 == 1 ) then
                    yrp = lyr2
                    mop = firstmo2
                    moq = mop
                    if ( mo < moq ) then
                        yrq = yr - 1
                    else
                        yrq = yr
                    end if
                else
                    yrp = lyr2
                    mop = mo
                    moq = mo
                    yrq = yr
                endif
                do jz=1,nz
                    do jy=1,ny
                        do jx=1,nx
                            if ( field(jx,jy,jz,mo,yr,iens) < 1e33 .and. &
                                 pattern(jx,jy,jz,mop,yrp) < 1e33 .and. &
                                 series(moq,yrq) < 1e33 ) then
                                if ( .false. .and. jx == (nx+1)/2 .and.jy == (ny+1)/2 .and. &
                                    nz == (nz+1)/2 ) then
                                    print *,'field was ',field(jx,jy,jz,mo,yr,iens),mo,yr,iens
                                    print *,' b,data = ',pattern(jx,jy,jz,mop,yrp) &
                                        ,mop,yrp,series(moq,yrq),moq,yrq
                                end if
                                field(jx,jy,jz,mo,yr,iens) = field(jx,jy,jz,mo,yr,iens) - &
                                    pattern(jx,jy,jz,mop,yrp)*series(moq,yrq)
                                if ( .false. .and. jx == (nx+1)/2 .and. jy == (ny+1)/2 .and. &
                                    nz == (nz+1)/2 ) then
                                    print *,'field is  ', field(jx,jy,jz,mo,yr,iens)
                                end if
                            else
                                field(jx,jy,jz,mo,yr,iens) = 3e33
                            end if
                        end do
                    end do
                end do
            end do
        end do
    end do

!   write out

    if ( firstyr2 == 0 .and. firstmo2 == nperyear .and. nt2 == 1 ) then
        title = trim(title)//' minus annual '
    else if ( nt2 == 1 ) then
        title = trim(title)//' minus '
    else
        if ( nperyear == 4 ) then
            title = trim(title)//' minus seasonal '
        else if ( nperyear == 12 ) then
            title = trim(title)//' minus monthly '
        else if ( nperyear >= 260 .and. nperyear <= 366 ) then
            title = trim(title)//' minus daily '
        else
            title = trim(title)//' minus seasonally varying '
        end if
    endif
    title = trim(title)//' '//trim(variable)//' from '// &
        trim(patternfile)//' times '//trim(var)//' from '//seriesfile
    lvars(1) = trim(lvars(1))//' - '//trim(lvars2(1))//'*'//trim(var)
    do iens=nens1,nens2
        i = index(outfile,'%') + index(outfile,'%%')
        if ( nens2 > nens1 .and. i == 0 ) then
            write(0,*) 'subtractfield: error: output file ', &
                'name does not contain % or ++: ',trim(outfile)
            call exit(-1)
        end if
        file = outfile
        if ( i /= 0 ) call filloutens(file,iens)
        if ( index(file,'.nc') == 0 ) then
            i = index(file,'.ctl')
            if ( i == 0 ) i = len_trim(file)+1
            datfile = file(:i-1)//'.grd'
            inquire(file=trim(file),exist=lexist)
            if ( lexist ) then
                print *,'outfile ',trim(file),' already exists, overwrite?'
                read(*,*) yesno
                if ( yesno == 'y' .or. yesno == 'Y' ) then
                    open(1,file=trim(outfile))
                    close(1,status='delete')
                    open(1,file=trim(datfile))
                    close(1,status='delete')
                end if
            end if
            if ( ncid /= -1 ) then
                ivars(1,1) = nz
                ivars(2,1) = 99
            end if
            call writectl(file,datfile,nx,xx,ny,yy,nz,zz, &
                nt,nperyear,firstyr,firstmo,3e33,title,1,vars,ivars &
                ,lvars,units)
            open(1,file=trim(datfile),form='unformatted',access &
                ='direct',recl=nx*ny*nz*recfa4)
            yr = firstyr
            mo = firstmo
            do it=1,nt
                write(1,rec=it) (((field(jx,jy,jz,mo,yr,iens), &
                    jx=1,nx),jy=1,ny),jz=1,nz)
                mo = mo + 1
                if ( mo > nperyear ) then
                    mo = 1
                    yr = yr + 1
                end if
            end do
            close(1)
        else
            if ( iens == nens1 ) allocate(itimeaxis(nt))
            call enswritenc(file,ncid,ntvarid,itimeaxis,nt,nx,xx,ny &
                ,yy,nz,zz,lz,nt,nperyear,firstyr,firstmo,ltime,3e33,title,history,1 &
                ,vars,ivars,lvars,svars,units,cell_methods,metadata1,0,0)
            yr = firstyr
            mo = firstmo
            irec = 0
            do it=1,nt
                if ( nperyear == 366 .and. mo == 60 .and. &
                leap(yr) == 1 ) cycle
                irec = irec + 1
                call writencslice(ncid,ntvarid,itimeaxis,nt,ivars &
                    ,field(1,1,1,mo,yr,iens),nx,ny,nz,nx,ny,nz,irec,1)
                mo = mo + 1
                if ( mo > nperyear ) then
                    mo = 1
                    yr = yr + 1
                end if
            end do
        end if
    end do
end program subtractfield
