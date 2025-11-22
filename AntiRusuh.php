<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;

class AntiRusuh
{
    protected function ownersList()
    {
        $owners = env('OWNERS', '');
        if ($owners === '') {
            return [];
        }
        $list = array_map('trim', explode(',', $owners));
        return array_filter($list);
    }

    public function handle($request, Closure $next)
    {
        $user = Auth::user();
        if (!$user) {
            return $next($request);
        }

        $owners = $this->ownersList();
        $isOwner = in_array($user->email, $owners);

        if ($isOwner) {
            return $next($request);
        }

        $path = $request->path();
        $method = strtoupper($request->method());

        $protectedMenus = [
            'admin/nodes',
            'admin/locations',
            'admin/nests',
            'admin/eggs',
            'admin/settings',
            'admin/allocations'
        ];

        foreach ($protectedMenus as $menu) {
            if (str_starts_with($path, $menu)) {
                Log::warning("[MenuProtect] {$user->email} tried to access {$path}");
                return response()->view('errors.protect', [
                    'title' => 'Akses Ditolak',
                    'message' => 'Menu ini hanya dapat diakses oleh Owner.'
                ], 403);
            }
        }

        if (preg_match('/admin\/users\/(\d+)/', $path, $m) && $method === 'DELETE') {
            Log::warning("[AntiRusuh] {$user->email} tried to delete user ID {$m[1]}");
            return response()->view('errors.protect', [
                'title' => 'Akses Ditolak',
                'message' => 'Hanya owner yang boleh menghapus user.'
            ], 403);
        }

        if (preg_match('/admin\/servers\/(\d+)/', $path, $m) && $method === 'DELETE') {
            $serverId = intval($m[1]);
            $server = Server::find($serverId);
            if ($server && $server->owner_id !== $user->id) {
                Log::warning("[AntiRusuh] {$user->email} attempted delete server {$serverId}");
                return response()->view('errors.protect', [
                    'title' => 'Tidak Diizinkan',
                    'message' => 'Kamu tidak bisa menghapus panel milik user lain.'
                ], 403);
            }
        }

        if (preg_match('/server[s]?\/(\d+)/', $path, $match)) {
            $serverId = intval($match[1]);
            $server = Server::find($serverId);
            if ($server && $server->owner_id !== $user->id) {
                Log::warning("[AntiNgintip] {$user->email} tried to open server {$serverId}");
                return response()->view('errors.protect', [
                    'title' => 'Akses Ditolak',
                    'message' => 'Kamu tidak punya izin untuk melihat panel ini.'
                ], 403);
            }
        }

        if (preg_match('/admin\/servers\/(\d+)\/(build|startup)/', $path, $m)) {
            $serverId = intval($m[1]);
            $server = Server::find($serverId);
            if ($server && $server->owner_id !== $user->id) {
                Log::warning("[AntiRusuh] {$user->email} attempted modify server {$serverId}");
                return response()->view('errors.protect', [
                    'title' => 'Tidak Diizinkan',
                    'message' => 'Kamu tidak memiliki izin untuk mengubah server ini.'
                ], 403);
            }
        }

        return $next($request);
    }
}
