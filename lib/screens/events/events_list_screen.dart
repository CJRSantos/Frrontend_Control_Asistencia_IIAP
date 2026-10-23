import '../../widgets/event_image_widget.dart';
import 'package:flutter/material.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../services/event_service.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../../utils/responsive.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';

class EventsListScreen extends StatefulWidget {
  const EventsListScreen({super.key});

  @override
  State<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends State<EventsListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      await EventService.getEvents();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Color _getTypeColor(EventType type) {
    switch (type) {
      case EventType.CAPACITACION:
        return const Color(0xFF2563EB);
      case EventType.REUNION:
        return const Color(0xFF0D9488);
      case EventType.INSTITUCIONAL:
        return const Color(0xFF7C3AED);
      case EventType.TALLER:
        return const Color(0xFFEA580C);
      case EventType.CONFERENCIA:
        return const Color(0xFFDB2777);
      case EventType.OTRO:
        return const Color(0xFF4B5563);
    }
  }

  String _formatDate(DateTime date) {
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'p. m.' : 'a. m.';
    return '${hour.toString().padLeft(2, '0')}:$minute $ampm';
  }

  List<EventModel> _filterEvents(List<EventModel> allEvents, int tabIndex, UserModel? currentUser) {
    final query = _searchQuery.toLowerCase().trim();
    final now = DateTime.now();

    return allEvents.where((e) {
      final matchesQuery = query.isEmpty ||
          e.title.toLowerCase().contains(query) ||
          e.location.toLowerCase().contains(query) ||
          e.description.toLowerCase().contains(query);

      if (!matchesQuery) return false;

      if (tabIndex == 1) {
        // En curso o Próximos
        return e.endDate.isAfter(now) || e.isActiveNow;
      } else if (tabIndex == 2) {
        // Finalizados
        return e.endDate.isBefore(now) && !e.isActiveNow;
      } else if (tabIndex == 3) {
        // Mis Asistencias
        return currentUser != null && e.isUserRegistered(currentUser.id);
      }
      return true; // Todos
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = StorageService.currentUser;
    final canCreate = currentUser?.canManageAttendanceQr == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Eventos Institucionales',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: ThemeService.cardBg(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ValueListenableBuilder<List<EventModel>>(
            valueListenable: EventService.eventsNotifier,
            builder: (context, allEvents, _) {
              final myCount = allEvents.where((e) => currentUser != null && e.isUserRegistered(currentUser.id)).length;

              return TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: ThemeService.primaryColor(context),
                labelColor: ThemeService.primaryColor(context),
                unselectedLabelColor: isDark ? Colors.white60 : const Color(0xFF64748B),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  const Tab(text: 'Todos'),
                  const Tab(text: 'Próximos'),
                  const Tab(text: 'Finalizados'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_rounded, size: 14),
                        const SizedBox(width: 5),
                        const Text('Mis Asistencias'),
                        if (myCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$myCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              backgroundColor: ThemeService.primaryColor(context),
              onPressed: () async {
                final created = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                );
                if (created == true) {
                  _loadEvents();
                }
              },
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text(
                'Crear Evento',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Responsive.constrained(
                context,
                maxTabletWidth: 700,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Buscar eventos por título o lugar...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: ThemeService.primaryColor(context),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? ThemeService.cardBg(context) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDark ? ThemeService.cardBorder(context) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDark ? ThemeService.cardBorder(context) : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Contenido por pestañas
            Expanded(
              child: ValueListenableBuilder<List<EventModel>>(
                valueListenable: EventService.eventsNotifier,
                builder: (context, allEvents, _) {
                  if (_isLoading && allEvents.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEventList(context, _filterEvents(allEvents, 0, currentUser), currentUser, 0),
                      _buildEventList(context, _filterEvents(allEvents, 1, currentUser), currentUser, 1),
                      _buildEventList(context, _filterEvents(allEvents, 2, currentUser), currentUser, 2),
                      _buildEventList(context, _filterEvents(allEvents, 3, currentUser), currentUser, 3),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList(BuildContext context, List<EventModel> events, UserModel? currentUser, int tabIndex) {
    if (events.isEmpty) {
      final isMyAttendanceTab = tabIndex == 3;

      return RefreshIndicator(
        onRefresh: _loadEvents,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isMyAttendanceTab
                          ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                          : ThemeService.primaryColor(context).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isMyAttendanceTab ? Icons.verified_rounded : Icons.event_busy_rounded,
                      size: 48,
                      color: isMyAttendanceTab ? const Color(0xFF16A34A) : ThemeService.primaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isMyAttendanceTab ? 'Sin asistencias registradas' : 'No se encontraron eventos',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No hay eventos que coincidan con la búsqueda.'
                        : (isMyAttendanceTab
                            ? 'Aún no has registrado tu asistencia a ningún evento institucional. Cuando escanees el QR de un evento o seas acreditado, tu constancia aparecerá aquí.'
                            : 'No hay eventos disponibles en esta sección.'),
                    style: TextStyle(color: ThemeService.subtextColor(context), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  if (isMyAttendanceTab && _searchQuery.isEmpty) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeService.primaryColor(context),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: () => _tabController.animateTo(1),
                      icon: const Icon(Icons.explore_outlined, size: 18),
                      label: const Text('Explorar Próximos Eventos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final event = events[index];
          return _buildEventCard(context, event, currentUser);
        },
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventModel event, UserModel? currentUser) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final typeColor = _getTypeColor(event.type);
    final isRegistered = currentUser != null && event.isUserRegistered(currentUser.id);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(event: event),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ThemeService.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: event.isActiveNow
                ? const Color(0xFF16A34A).withValues(alpha: 0.6)
                : ThemeService.cardBorder(context),
            width: event.isActiveNow ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.imageUrl != null && event.imageUrl!.trim().isNotEmpty) ...[
              Container(
                height: 120,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                child: EventImageWidget(
                  imageUrl: event.imageUrl,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
            // Fila superior: Tipo + Estado
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    event.type.displayName.toUpperCase(),
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (event.isEventosMirror) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync_rounded, size: 11, color: Color(0xFF6366F1)),
                        SizedBox(width: 4),
                        Text(
                          'Sistema de Eventos',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (event.requiresAttendance) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_2_rounded, size: 12, color: Color(0xFF2563EB)),
                            SizedBox(width: 4),
                            Text(
                              'QR',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: event.isActiveNow
                            ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                            : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 7,
                            color: event.isActiveNow ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.isActiveNow ? 'En curso' : event.status.displayName,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: event.isActiveNow ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Título
            Text(
              event.title,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 8),

            // Fecha y Horario
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 13, color: ThemeService.primaryColor(context)),
                    const SizedBox(width: 5),
                    Text(
                      _formatDate(event.startDate),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_rounded, size: 13, color: ThemeService.subtextColor(context)),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatTime(event.startDate)} - ${_formatTime(event.endDate)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ThemeService.subtextColor(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Ubicación
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 13, color: ThemeService.subtextColor(context)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    event.location,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ThemeService.subtextColor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Fila inferior: Asistentes y Badge de Registro
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.people_alt_outlined, size: 14, color: ThemeService.primaryColor(context)),
                    const SizedBox(width: 5),
                    Text(
                      '${event.attendees.length} asistentes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeService.primaryColor(context),
                      ),
                    ),
                  ],
                ),
                if (isRegistered) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF16A34A)),
                        SizedBox(width: 4),
                        Text(
                          'Asistencia Confirmada',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver detalles',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ThemeService.subtextColor(context),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 16, color: ThemeService.subtextColor(context)),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
