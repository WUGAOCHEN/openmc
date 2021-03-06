module global

  use ace_header,       only: Nuclide, SAlphaBeta, xsListing, NuclideMicroXS, &
                              MaterialMacroXS, Nuclide0K
  use bank_header,      only: Bank
  use cmfd_header
  use constants
  use dict_header,      only: DictCharInt, DictIntInt
  use geometry_header,  only: Cell, Universe, Lattice, LatticeContainer
  use material_header,  only: Material
  use mesh_header,      only: RegularMesh
  use plot_header,      only: ObjectPlot
  use set_header,       only: SetInt
  use surface_header,   only: SurfaceContainer
  use source_header,    only: SourceDistribution
  use tally_header,     only: TallyObject, TallyMap, TallyResult
  use trigger_header,   only: KTrigger
  use timer_header,     only: Timer

#ifdef MPIF08
  use mpi_f08
#endif

  implicit none

  ! ============================================================================
  ! GEOMETRY-RELATED VARIABLES

  ! Main arrays
  type(Cell),             allocatable, target :: cells(:)
  type(Universe),         allocatable, target :: universes(:)
  type(LatticeContainer), allocatable, target :: lattices(:)
  type(SurfaceContainer), allocatable, target :: surfaces(:)
  type(Material),         allocatable, target :: materials(:)
  type(ObjectPlot),       allocatable, target :: plots(:)

  ! Size of main arrays
  integer :: n_cells     ! # of cells
  integer :: n_universes ! # of universes
  integer :: n_lattices  ! # of lattices
  integer :: n_surfaces  ! # of surfaces
  integer :: n_materials ! # of materials
  integer :: n_plots     ! # of plots

  ! These dictionaries provide a fast lookup mechanism -- the key is the
  ! user-specified identifier and the value is the index in the corresponding
  ! array
  type(DictIntInt) :: cell_dict
  type(DictIntInt) :: universe_dict
  type(DictIntInt) :: lattice_dict
  type(DictIntInt) :: surface_dict
  type(DictIntInt) :: material_dict
  type(DictIntInt) :: mesh_dict
  type(DictIntInt) :: tally_dict
  type(DictIntInt) :: plot_dict

  ! Number of lost particles
  integer :: n_lost_particles

  ! ============================================================================
  ! CROSS SECTION RELATED VARIABLES

  ! Cross section arrays
  type(Nuclide),    allocatable, target :: nuclides(:)    ! Nuclide cross-sections
  type(SAlphaBeta), allocatable, target :: sab_tables(:)  ! S(a,b) tables
  type(XsListing),  allocatable, target :: xs_listings(:) ! cross_sections.xml listings

  ! Cross section caches
  type(NuclideMicroXS), allocatable :: micro_xs(:)  ! Cache for each nuclide
  type(MaterialMacroXS)             :: material_xs  ! Cache for current material

  integer :: n_nuclides_total ! Number of nuclide cross section tables
  integer :: n_sab_tables     ! Number of S(a,b) thermal scattering tables
  integer :: n_listings       ! Number of listings in cross_sections.xml

  ! Minimum/maximum energies
  real(8) :: energy_min_neutron = ZERO
  real(8) :: energy_max_neutron = INFINITY

  ! Dictionaries to look up cross sections and listings
  type(DictCharInt) :: nuclide_dict
  type(DictCharInt) :: sab_dict
  type(DictCharInt) :: xs_listing_dict

  ! Unreoslved resonance probablity tables
  logical :: urr_ptables_on = .true.

  ! Default xs identifier (e.g. 70c)
  character(3):: default_xs

  ! What to assume for expanding natural elements
  integer :: default_expand = ENDF_BVII1

  ! ============================================================================
  ! TALLY-RELATED VARIABLES

  type(RegularMesh), allocatable, target :: meshes(:)
  type(TallyObject),    allocatable, target :: tallies(:)
  integer, allocatable :: matching_bins(:)

  ! Pointers for different tallies
  type(TallyObject), pointer :: user_tallies(:) => null()
  type(TallyObject), pointer :: cmfd_tallies(:) => null()

  ! Starting index (minus 1) in tallies for each tally group
  integer :: i_user_tallies = -1
  integer :: i_cmfd_tallies = -1

  ! Active tally lists
  type(SetInt) :: active_analog_tallies
  type(SetInt) :: active_tracklength_tallies
  type(SetInt) :: active_current_tallies
  type(SetInt) :: active_collision_tallies
  type(SetInt) :: active_tallies
!$omp threadprivate(active_analog_tallies, active_tracklength_tallies, &
!$omp&              active_current_tallies, active_collision_tallies, &
!$omp&              active_tallies)

  ! Global tallies
  !   1) collision estimate of k-eff
  !   2) absorption estimate of k-eff
  !   3) track-length estimate of k-eff
  !   4) leakage fraction

  type(TallyResult), allocatable, target :: global_tallies(:)

  ! It is possible to protect accumulate operations on global tallies by using
  ! an atomic update. However, when multiple threads accumulate to the same
  ! global tally, it can cause a higher cache miss rate due to
  ! invalidation. Thus, we use threadprivate variables to accumulate global
  ! tallies and then reduce at the end of a generation.
  real(8) :: global_tally_collision   = ZERO
  real(8) :: global_tally_absorption  = ZERO
  real(8) :: global_tally_tracklength = ZERO
  real(8) :: global_tally_leakage     = ZERO
!$omp threadprivate(global_tally_collision, global_tally_absorption, &
!$omp&              global_tally_tracklength, global_tally_leakage)

  ! Tally map structure
  type(TallyMap), allocatable :: tally_maps(:)

  integer :: n_meshes       = 0 ! # of structured meshes
  integer :: n_user_meshes  = 0 ! # of structured user meshes
  integer :: n_tallies      = 0 ! # of tallies
  integer :: n_user_tallies = 0 ! # of user tallies

  ! Normalization for statistics
  integer :: n_realizations = 0 ! # of independent realizations
  real(8) :: total_weight       ! total starting particle weight in realization

  ! Flag for turning tallies on
  logical :: tallies_on = .false.
  logical :: active_batches = .false.

  ! Assume all tallies are spatially distinct
  logical :: assume_separate = .false.

  ! Use confidence intervals for results instead of standard deviations
  logical :: confidence_intervals = .false.

  ! ============================================================================
  ! EIGENVALUE SIMULATION VARIABLES

  integer(8) :: n_particles = 0   ! # of particles per generation
  integer    :: n_batches         ! # of batches
  integer    :: n_inactive        ! # of inactive batches
  integer    :: n_active          ! # of active batches
  integer    :: gen_per_batch = 1 ! # of generations per batch
  integer    :: current_batch = 0 ! current batch
  integer    :: current_gen   = 0 ! current generation within a batch
  integer    :: overall_gen   = 0 ! overall generation in the run

  ! ============================================================================
  ! TALLY PRECISION TRIGGER VARIABLES

  integer        :: n_max_batches             ! max # of batches
  integer        :: n_batch_interval = 1      ! batch interval for triggers
  logical        :: pred_batches = .false.    ! predict batches for triggers
  logical        :: trigger_on = .false.      ! flag for turning triggers on/off
  type(KTrigger) :: keff_trigger              ! trigger for k-effective
  logical :: satisfy_triggers = .false.       ! whether triggers are satisfied

  ! External source
  type(SourceDistribution), allocatable :: external_source(:)

  ! Source and fission bank
  type(Bank), allocatable, target :: source_bank(:)
  type(Bank), allocatable, target :: fission_bank(:)
#ifdef _OPENMP
  type(Bank), allocatable, target :: master_fission_bank(:)
#endif
  integer(8) :: n_bank       ! # of sites in fission bank
  integer(8) :: work         ! number of particles per processor
  integer(8), allocatable :: work_index(:) ! starting index in source bank for each process
  integer(8) :: current_work ! index in source bank of current history simulated

  ! Temporary k-effective values
  real(8), allocatable :: k_generation(:) ! single-generation estimates of k
  real(8) :: keff = ONE       ! average k over active batches
  real(8) :: keff_std         ! standard deviation of average k
  real(8) :: k_col_abs = ZERO ! sum over batches of k_collision * k_absorption
  real(8) :: k_col_tra = ZERO ! sum over batches of k_collision * k_tracklength
  real(8) :: k_abs_tra = ZERO ! sum over batches of k_absorption * k_tracklength
  real(8) :: k_combined(2)    ! combined best estimate of k-effective

  ! Shannon entropy
  logical :: entropy_on = .false.
  real(8), allocatable :: entropy(:)         ! shannon entropy at each generation
  real(8), allocatable :: entropy_p(:,:,:,:) ! % of source sites in each cell
  type(RegularMesh), pointer :: entropy_mesh

  ! Uniform fission source weighting
  logical :: ufs = .false.
  type(RegularMesh), pointer :: ufs_mesh => null()
  real(8), allocatable :: source_frac(:,:,:,:)

  ! Write source at end of simulation
  logical :: source_separate = .false.
  logical :: source_write = .true.
  logical :: source_latest = .false.

  ! ============================================================================
  ! PARALLEL PROCESSING VARIABLES

  ! The defaults set here for the number of processors, rank, and master and
  ! mpi_enabled flag are for when MPI is not being used at all, i.e. a serial
  ! run. In this case, these variables are still used at times.

  integer :: n_procs     = 1       ! number of processes
  integer :: rank        = 0       ! rank of process
  logical :: master      = .true.  ! master process?
  logical :: mpi_enabled = .false. ! is MPI in use and initialized?
  integer :: mpi_err               ! MPI error code
#ifdef MPIF08
  type(MPI_Datatype) :: MPI_BANK
  type(MPI_Datatype) :: MPI_TALLYRESULT
#else
  integer :: MPI_BANK              ! MPI datatype for fission bank
  integer :: MPI_TALLYRESULT       ! MPI datatype for TallyResult
#endif

#ifdef _OPENMP
  integer :: n_threads = NONE      ! number of OpenMP threads
  integer :: thread_id             ! ID of a given thread
#endif

  ! No reduction at end of batch
  logical :: reduce_tallies = .true.

  ! ============================================================================
  ! TIMING VARIABLES

  type(Timer) :: time_total         ! timer for total run
  type(Timer) :: time_initialize    ! timer for initialization
  type(Timer) :: time_read_xs       ! timer for reading cross sections
  type(Timer) :: time_unionize      ! timer for material xs-energy grid union
  type(Timer) :: time_bank          ! timer for fission bank synchronization
  type(Timer) :: time_bank_sample   ! timer for fission bank sampling
  type(Timer) :: time_bank_sendrecv ! timer for fission bank SEND/RECV
  type(Timer) :: time_tallies       ! timer for accumulate tallies
  type(Timer) :: time_inactive      ! timer for inactive batches
  type(Timer) :: time_active        ! timer for active batches
  type(Timer) :: time_transport     ! timer for transport only
  type(Timer) :: time_finalize      ! timer for finalization

  ! ===========================================================================
  ! VARIANCE REDUCTION VARIABLES

  logical :: survival_biasing = .false.
  real(8) :: weight_cutoff = 0.25_8
  real(8) :: weight_survive = ONE

  ! ============================================================================
  ! MISCELLANEOUS VARIABLES

  ! Mode to run in (fixed source, eigenvalue, plotting, etc)
  integer :: run_mode = NONE

  ! Restart run
  logical :: restart_run = .false.
  integer :: restart_batch

  character(MAX_FILE_LEN) :: path_input            ! Path to input file
  character(MAX_FILE_LEN) :: path_cross_sections   ! Path to cross_sections.xml
  character(MAX_FILE_LEN) :: path_source = ''      ! Path to binary source
  character(MAX_FILE_LEN) :: path_state_point      ! Path to binary state point
  character(MAX_FILE_LEN) :: path_source_point     ! Path to binary source point
  character(MAX_FILE_LEN) :: path_particle_restart ! Path to particle restart
  character(MAX_FILE_LEN) :: path_output = ''      ! Path to output directory

  ! The verbosity controls how much information will be printed to the
  ! screen and in logs
  integer :: verbosity = 7

  ! Flag for enabling cell overlap checking during transport
  logical                  :: check_overlaps = .false.
  integer(8), allocatable  :: overlap_check_cnt(:)

  ! Trace for single particle
  logical    :: trace
  integer    :: trace_batch
  integer    :: trace_gen
  integer(8) :: trace_particle

  ! Particle tracks
  logical :: write_all_tracks = .false.
  integer, allocatable :: track_identifiers(:,:)

  ! Particle restart run
  logical :: particle_restart_run = .false.

  ! Number of distribcell maps
  integer :: n_maps

  ! Write out initial source
  logical :: write_initial_source = .false.

  ! ============================================================================
  ! CMFD VARIABLES

  ! Main object
  type(cmfd_type) :: cmfd

  ! Is CMFD active
  logical :: cmfd_run = .false.

  ! Timing objects
  type(Timer) :: time_cmfd      ! timer for whole cmfd calculation
  type(Timer) :: time_cmfdbuild ! timer for matrix build
  type(Timer) :: time_cmfdsolve ! timer for solver

  ! Flag for active core map
  logical :: cmfd_coremap = .false.

  ! Flag to reset dhats to zero
  logical :: dhat_reset = .false.

  ! Flag to activate neutronic feedback via source weights
  logical :: cmfd_feedback = .false.

  ! User-defined tally information
  integer :: n_cmfd_meshes  = 1 ! # of structured meshes
  integer :: n_cmfd_tallies = 3 ! # of user-defined tallies

  ! Adjoint method type
  character(len=10) :: cmfd_adjoint_type = 'physical'

  ! Number of incomplete ilu factorization levels
  integer :: cmfd_ilu_levels = 1

  ! Batch to begin cmfd
  integer :: cmfd_begin = 1

  ! Tally reset list
  integer :: n_cmfd_resets
  type(SetInt) :: cmfd_reset

  ! Compute effective downscatter cross section
  logical :: cmfd_downscatter = .false.

  ! Convergence monitoring
  logical :: cmfd_power_monitor = .false.

  ! Cmfd output
  logical :: cmfd_write_matrices = .false.

  ! Run an adjoint calculation (last batch only)
  logical :: cmfd_run_adjoint = .false.

  ! CMFD run logicals
  logical :: cmfd_on             = .false.

  ! CMFD display info
  character(len=25) :: cmfd_display = 'balance'

  ! Estimate of spectral radius of CMFD matrices and tolerances
  real(8) :: cmfd_spectral = ZERO
  real(8) :: cmfd_shift = 1.e6
  real(8) :: cmfd_ktol = 1.e-8_8
  real(8) :: cmfd_stol = 1.e-8_8
  real(8) :: cmfd_atoli = 1.e-10_8
  real(8) :: cmfd_rtoli = 1.e-5_8

  ! Information about state points to be written
  integer :: n_state_points = 0
  type(SetInt) :: statepoint_batch

  ! Information about source points to be written
  integer :: n_source_points = 0
  type(SetInt) :: sourcepoint_batch

  ! Various output options
  logical :: output_summary = .false.
  logical :: output_xs      = .false.
  logical :: output_tallies = .true.

  ! ============================================================================
  ! RESONANCE SCATTERING VARIABLES

  logical :: treat_res_scat = .false. ! is resonance scattering treated?
  integer :: n_res_scatterers_total = 0 ! total number of resonant scatterers
  type(Nuclide0K), allocatable, target :: nuclides_0K(:) ! 0K nuclides info

!$omp threadprivate(micro_xs, material_xs, fission_bank, n_bank, &
!$omp&              trace, thread_id, current_work, matching_bins)

contains

!===============================================================================
! FREE_MEMORY deallocates and clears  all global allocatable arrays in the
! program
!===============================================================================

  subroutine free_memory()

    integer :: i ! Loop Index

    ! Deallocate cells, surfaces, materials
    if (allocated(cells)) deallocate(cells)
    if (allocated(universes)) deallocate(universes)
    if (allocated(lattices)) deallocate(lattices)
    if (allocated(surfaces)) deallocate(surfaces)
    if (allocated(materials)) deallocate(materials)
    if (allocated(plots)) deallocate(plots)

    ! Deallocate geometry debugging information
    if (allocated(overlap_check_cnt)) deallocate(overlap_check_cnt)

    ! Deallocate cross section data, listings, and cache
    if (allocated(nuclides)) then
    ! First call the clear routines
      do i = 1, size(nuclides)
        call nuclides(i) % clear()
      end do

      ! WARNING: The following statement should work but doesn't under gfortran
      ! 4.6 because of a bug. Technically, commenting this out leaves a memory
      ! leak.

      ! deallocate(nuclides)
    end if

    if (allocated(nuclides_0K)) then
      deallocate(nuclides_0K)
    end if

    if (allocated(sab_tables)) deallocate(sab_tables)
    if (allocated(xs_listings)) deallocate(xs_listings)
    if (allocated(micro_xs)) deallocate(micro_xs)

    ! Deallocate external source
    if (allocated(external_source)) deallocate(external_source)

    ! Deallocate k and entropy
    if (allocated(k_generation)) deallocate(k_generation)
    if (allocated(entropy)) deallocate(entropy)
    if (allocated(entropy_p)) deallocate(entropy_p)

    ! Deallocate tally-related arrays
    if (allocated(global_tallies)) deallocate(global_tallies)
    if (allocated(meshes)) deallocate(meshes)
    if (allocated(tallies)) deallocate(tallies)
    if (allocated(matching_bins)) deallocate(matching_bins)
    if (allocated(tally_maps)) deallocate(tally_maps)

    ! Deallocate fission and source bank and entropy
!$omp parallel
    if (allocated(fission_bank)) deallocate(fission_bank)
!$omp end parallel
#ifdef _OPENMP
    if (allocated(master_fission_bank)) deallocate(master_fission_bank)
#endif
    if (allocated(source_bank)) deallocate(source_bank)
    if (allocated(entropy_p)) deallocate(entropy_p)

    ! Deallocate array of work indices
    if (allocated(work_index)) deallocate(work_index)

    ! Deallocate CMFD
    call deallocate_cmfd(cmfd)

    ! Deallocate tally node lists
    call active_analog_tallies % clear()
    call active_tracklength_tallies % clear()
    call active_current_tallies % clear()
    call active_collision_tallies % clear()
    call active_tallies % clear()

    ! Deallocate track_identifiers
    if (allocated(track_identifiers)) deallocate(track_identifiers)

    ! Deallocate dictionaries
    call cell_dict % clear()
    call universe_dict % clear()
    call lattice_dict % clear()
    call surface_dict % clear()
    call material_dict % clear()
    call mesh_dict % clear()
    call tally_dict % clear()
    call plot_dict % clear()
    call nuclide_dict % clear()
    call sab_dict % clear()
    call xs_listing_dict % clear()

    ! Clear statepoint and sourcepoint batch set
    call statepoint_batch % clear()
    call sourcepoint_batch % clear()

    ! Deallocate entropy mesh
    if (associated(entropy_mesh)) then
      if (allocated(entropy_mesh % lower_left)) &
           deallocate(entropy_mesh % lower_left)
      if (allocated(entropy_mesh % upper_right)) &
           deallocate(entropy_mesh % upper_right)
      if (allocated(entropy_mesh % width)) deallocate(entropy_mesh % width)
      deallocate(entropy_mesh)
    end if

    ! Deallocate ufs
    if (allocated(source_frac)) deallocate(source_frac)
    if (associated(ufs_mesh)) then
        if (allocated(ufs_mesh % lower_left)) deallocate(ufs_mesh % lower_left)
        if (allocated(ufs_mesh % upper_right)) &
             deallocate(ufs_mesh % upper_right)
        if (allocated(ufs_mesh % width)) deallocate(ufs_mesh % width)
        deallocate(ufs_mesh)
    end if

  end subroutine free_memory

end module global
